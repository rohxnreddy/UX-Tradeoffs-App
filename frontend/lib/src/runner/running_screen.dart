// lib/src/runner/running_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'test_model.dart';
import 'test_runner.dart';

class RunningScreen extends StatefulWidget {
  final List<TestId>                        selectedTests;
  final void Function(List<TestResult> r)   onDone;

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
  bool    _done = false;
  String  _overallMsg = 'Preparing…';
  List<TestResult> _results = [];

  static const _testColors = {
    TestId.vmaf:    AppTheme.vmafColor,
    TestId.peaq:    AppTheme.peaqColor,
    TestId.pesq:    AppTheme.pesqColor,
    TestId.iqa:     AppTheme.iqaColor,
    TestId.battery: AppTheme.battColor,
  };

  static const _testIcons = {
    TestId.vmaf:    Icons.videocam_outlined,
    TestId.peaq:    Icons.music_note_outlined,
    TestId.pesq:    Icons.record_voice_over_outlined,
    TestId.iqa:     Icons.image_outlined,
    TestId.battery: Icons.battery_charging_full_outlined,
  };

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);

    // Initialise progress entries
    for (final id in TestId.values) {
      final isSelected = widget.selectedTests.contains(id);
      _progress[id] = TestProgress(
        testId:   id,
        status:   isSelected ? TestStatus.pending : TestStatus.skipped,
        message:  isSelected ? 'Waiting…' : 'Skipped',
        fraction: 0,
      );
    }

    _start();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _start() {
    final runner = TestRunner(
      selectedTests: widget.selectedTests,
      onProgress:    (p) {
        if (!mounted) return;
        setState(() {
          _progress[p.testId] = p;
          if (p.status == TestStatus.running) {
            _currentTest = p.testId;
            _overallMsg  = p.message;
          }
        });
      },
    );

    runner.run().then((results) {
      if (!mounted) return;
      setState(() {
        _done     = true;
        _results  = results;
        _overallMsg = 'All tests complete!';
      });
      // Short delay so user sees "complete" before navigating
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) widget.onDone(results);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 36),

            // ── Central status ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  // Pulse ring
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) => Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.surface,
                        border: Border.all(
                          color: _done
                              ? AppTheme.good
                              : AppTheme.accent
                                    .withOpacity(0.3 + 0.7 * _pulseCtrl.value),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_done ? AppTheme.good : AppTheme.accent)
                                .withOpacity(_done ? 0.25 : 0.1 + 0.15 * _pulseCtrl.value),
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

            // ── Test list ──────────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: allTests.map((def) {
                  final p     = _progress[def.id]!;
                  final color = _testColors[def.id]!;
                  final icon  = _testIcons[def.id]!;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TestProgressTile(
                      definition:  def,
                      progress:    p,
                      color:       color,
                      icon:        icon,
                      isCurrent:   _currentTest == def.id,
                      pulseCtrl:   _pulseCtrl,
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

// ── Progress tile ─────────────────────────────────────────────────────────────

class _TestProgressTile extends StatelessWidget {
  final TestDefinition    definition;
  final TestProgress      progress;
  final Color             color;
  final IconData          icon;
  final bool              isCurrent;
  final AnimationController pulseCtrl;

  const _TestProgressTile({
    required this.definition,
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
      trailing = const Icon(Icons.remove_circle_outline, color: AppTheme.textDim, size: 22);
    } else if (st == TestStatus.running) {
      trailing = AnimatedBuilder(
        animation: pulseCtrl,
        builder: (_, __) => SizedBox(
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
                  definition.title,
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
