// lib/src/runner/running_screen.dart
//
// Orchestrator — navigates to each test's dedicated page in sequence.
// Tests that need hardware (camera, mic, screen recording) each have their own
// full-screen page.  Battery runs in-process via BatteryRunner.
//
// Flow per selected test:
//   1. Mark test as "running" in the progress list.
//   2. Push the test's page via Navigator.push and await a TestResult.
//   3. Store result, mark done/failed, move to next test.
//   4. After all tests → auto-navigate to Results after 1.2 s.

import 'dart:async';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'test_model.dart';
import 'test_runner.dart';

// Test page imports — each test lives in its own file.
import '../tests/vmaf_test_page.dart';
import '../tests/peaq_test_page.dart';
import '../tests/pesq_test_page.dart';
import '../tests/iqa_test_page.dart';

class RunningScreen extends StatefulWidget {
  final List<TestId> selectedTests;
  final void Function(List<TestResult> r) onDone;

  const RunningScreen({
    super.key,
    required this.selectedTests,
    required this.onDone,
  });

  @override
  State<RunningScreen> createState() => _RunningScreenState();
}

class _RunningScreenState extends State<RunningScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  final Map<TestId, TestProgress> _progress = {};
  TestId? _currentTest;
  bool _done = false;
  String _overallMsg = 'Preparing…';
  final List<TestResult> _results = [];

  Completer<TestResult>? _vmafCompleter;

  // ── Design maps ──────────────────────────────────────────────────────────
  static const _testNames = {
    TestId.vmaf: 'Video Experience',
    TestId.peaq: 'Audio Quality',
    TestId.pesq: 'Voice Clarity',
    TestId.iqa: 'Camera Quality',
    TestId.battery: 'Battery Health',
  };

  static const _testColors = {
    TestId.vmaf: AppTheme.vmafColor,
    TestId.peaq: AppTheme.peaqColor,
    TestId.pesq: AppTheme.pesqColor,
    TestId.iqa: AppTheme.iqaColor,
    TestId.battery: AppTheme.battColor,
  };

  static const _testIcons = {
    TestId.vmaf: Icons.videocam_outlined,
    TestId.peaq: Icons.music_note_outlined,
    TestId.pesq: Icons.record_voice_over_outlined,
    TestId.iqa: Icons.image_outlined,
    TestId.battery: Icons.battery_charging_full_outlined,
  };

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    for (final id in TestId.values) {
      final selected = widget.selectedTests.contains(id);
      _progress[id] = TestProgress(
        testId: id,
        status: selected ? TestStatus.pending : TestStatus.skipped,
        message: selected ? 'Waiting…' : 'Skipped',
        fraction: 0,
      );
    }

    // Start after one frame so Navigator is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Orchestration ─────────────────────────────────────────────────────────

  Future<void> _runAll() async {
    for (final def in allTests) {
      if (!widget.selectedTests.contains(def.id)) {
        _results.add(TestResult(id: def.id, status: TestStatus.skipped));
        continue;
      }

      // Mark running
      if (!mounted) return;
      setState(() {
        _currentTest = def.id;
        _overallMsg = 'Running ${_testNames[def.id]}…';
        _progress[def.id] = TestProgress(
          testId: def.id,
          status: TestStatus.running,
          message: 'Starting ${_testNames[def.id]}…',
          fraction: 0,
        );
      });

      TestResult result;
      try {
        result = await _dispatchTest(def);
      } catch (e) {
        result = TestResult(
          id: def.id,
          status: TestStatus.failed,
          errorMessage: e.toString(),
          completedAt: DateTime.now(),
        );
      }

      _results.add(result);

      if (!mounted) return;
      setState(() {
        // If VMAF returned a placeholder (status=running), show it as uploading.
        final isVmafPending =
            result.id == TestId.vmaf && result.status == TestStatus.running;
        _progress[def.id] = TestProgress(
          testId: def.id,
          status: isVmafPending ? TestStatus.running : result.status,
          message: isVmafPending
              ? 'Uploading in background…'
              : result.status == TestStatus.done
              ? '${_testNames[def.id]} complete'
              : 'Failed: ${result.errorMessage}',
          fraction: isVmafPending ? 0.75 : 1,
        );
      });
    }

    // All done with foreground tests
    if (!mounted) return;

    // VMAF uploads in the background; always patch the placeholder before Results.
    // Important: the upload may finish *early* while other tests are still running.
    if (_vmafCompleter != null) {
      if (!_vmafCompleter!.isCompleted) {
        setState(() {
          _overallMsg = 'Finishing video upload…';
          _progress[TestId.vmaf] = TestProgress(
            testId: TestId.vmaf,
            status: TestStatus.running,
            message: 'Uploading in background…',
            fraction: 0.85,
          );
        });
      }

      final vmafResult = await _vmafCompleter!.future;

      // Patch the placeholder in _results.
      final idx = _results.indexWhere((r) => r.id == TestId.vmaf);
      if (idx != -1) _results[idx] = vmafResult;

      if (mounted) {
        setState(() {
          _progress[TestId.vmaf] = TestProgress(
            testId: TestId.vmaf,
            status: vmafResult.status,
            message: vmafResult.status == TestStatus.done
                ? '${_testNames[TestId.vmaf]} complete'
                : 'Failed: ${vmafResult.errorMessage}',
            fraction: 1,
          );
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _done = true;
      _overallMsg = 'All tests complete!';
    });

    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) widget.onDone(_results);
  }

  // ── Dispatcher: push the right page and await its TestResult ─────────────

  Future<TestResult> _dispatchTest(TestDefinition def) async {
    switch (def.id) {
      case TestId.vmaf:
        _vmafCompleter = Completer<TestResult>();
        return _pushPage(
          VmafTestPage(
            onProgressUpdate: (msg, frac) => _emitProgress(def.id, msg, frac),
            onResultReady: (result) {
              if (!(_vmafCompleter?.isCompleted ?? true)) {
                _vmafCompleter!.complete(result);
              }
              // Immediately update the progress UI once the background result finishes.
              if (mounted) {
                setState(() {
                  _progress[def.id] = TestProgress(
                    testId: def.id,
                    status: result.status,
                    fraction: 1,
                    message: result.status == TestStatus.done
                        ? '${_testNames[def.id]} complete'
                        : 'Failed: ${result.errorMessage}',
                  );
                });
              }
            },
          ),
        );

      case TestId.peaq:
        return _pushPage(
          PeaqTestPage(
            onProgressUpdate: (msg, frac) => _emitProgress(def.id, msg, frac),
          ),
        );

      case TestId.pesq:
        return _pushPage(
          PesqTestPage(
            onProgressUpdate: (msg, frac) => _emitProgress(def.id, msg, frac),
          ),
        );

      case TestId.iqa:
        return _pushPage(
          IqaTestPage(
            onProgressUpdate: (msg, frac) => _emitProgress(def.id, msg, frac),
          ),
        );

      case TestId.battery:
        // Battery has no UI — runs in-process with progress callbacks.
        final runner = BatteryRunner(
          onProgress: (p) {
            if (mounted) setState(() => _progress[p.testId] = p);
          },
        );
        return runner.run();
    }
  }

  /// Push [page], which must pop with a [TestResult].
  Future<TestResult> _pushPage(Widget page) async {
    final result = await Navigator.of(
      context,
    ).push<TestResult>(MaterialPageRoute(builder: (_) => page));
    if (result == null) {
      throw Exception('Test was cancelled or returned no result.');
    }
    return result;
  }

  void _emitProgress(TestId id, String msg, double frac) {
    if (!mounted) return;
    setState(() {
      _progress[id] = TestProgress(
        testId: id,
        status: TestStatus.running,
        message: msg,
        fraction: frac,
      );
      _overallMsg = msg;
    });
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 36),

            // ── Central status ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (context, _) => Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.surface,
                        border: Border.all(
                          color: _done
                              ? AppTheme.good
                              : AppTheme.accent.withOpacity(
                                  0.3 + 0.7 * _pulseCtrl.value,
                                ),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_done ? AppTheme.good : AppTheme.accent)
                                .withOpacity(
                                  _done ? 0.25 : 0.1 + 0.15 * _pulseCtrl.value,
                                ),
                            blurRadius: 32,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(
                        _done ? Icons.check_rounded : Icons.analytics_outlined,
                        color: _done ? AppTheme.good : AppTheme.accent,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: Text(
                      _overallMsg,
                      key: ValueKey(_overallMsg),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.textSec,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 36),

            // ── Test list ───────────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: allTests.map((def) {
                  final p = _progress[def.id]!;
                  final color = _testColors[def.id]!;
                  final icon = _testIcons[def.id]!;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TestProgressTile(
                      definition: def,
                      displayName: _testNames[def.id]!,
                      progress: p,
                      color: color,
                      icon: icon,
                      isCurrent: _currentTest == def.id,
                      pulseCtrl: _pulseCtrl,
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Progress tile (unchanged from original) ───────────────────────────────────

class _TestProgressTile extends StatelessWidget {
  final TestDefinition definition;
  final String displayName;
  final TestProgress progress;
  final Color color;
  final IconData icon;
  final bool isCurrent;
  final AnimationController pulseCtrl;

  const _TestProgressTile({
    required this.definition,
    required this.displayName,
    required this.progress,
    required this.color,
    required this.icon,
    required this.isCurrent,
    required this.pulseCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final st = progress.status;

    Widget trailing;
    if (st == TestStatus.done) {
      trailing = const Icon(Icons.check_circle, color: AppTheme.good, size: 22);
    } else if (st == TestStatus.failed) {
      trailing = const Icon(Icons.error_outline, color: AppTheme.bad, size: 22);
    } else if (st == TestStatus.skipped) {
      trailing = const Icon(
        Icons.remove_circle_outline,
        color: AppTheme.textDim,
        size: 22,
      );
    } else if (st == TestStatus.running) {
      trailing = AnimatedBuilder(
        animation: pulseCtrl,
        builder: (context, _) => SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: color.withOpacity(0.5 + 0.5 * pulseCtrl.value),
          ),
        ),
      );
    } else {
      trailing = Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.border),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isCurrent
            ? color.withOpacity(0.08)
            : (st == TestStatus.done || st == TestStatus.failed)
            ? AppTheme.surface
            : AppTheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent
              ? color.withOpacity(0.4)
              : st == TestStatus.done
              ? AppTheme.good.withOpacity(0.25)
              : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: st == TestStatus.skipped
                ? AppTheme.textDim
                : (st == TestStatus.done || isCurrent)
                ? color
                : AppTheme.textSec,
            size: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    color: st == TestStatus.skipped
                        ? AppTheme.textDim
                        : AppTheme.textPri,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isCurrent || st == TestStatus.failed) ...[
                  const SizedBox(height: 4),
                  Text(
                    progress.message,
                    style: TextStyle(
                      color: st == TestStatus.failed
                          ? AppTheme.bad
                          : AppTheme.textSec,
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (isCurrent && st == TestStatus.running) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress.fraction,
                      backgroundColor: AppTheme.border,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}
