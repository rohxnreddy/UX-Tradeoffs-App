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
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../core/app_config.dart';
import '../core/session_store.dart';
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
  Completer<TestResult>? _networkCompleter;

  // ── Suite-scoped monitors (battery/network) ───────────────────────────────
  DateTime? _suiteStartedAt;
  DateTime? _suiteEndedAt;

  // Battery (suite-level)
  final Battery _battery = Battery();
  Timer? _batteryPollTimer;
  int? _batteryStartLevel;
  int? _batteryEndLevel;
  BatteryState? _batteryStartState;
  BatteryState? _batteryEndState;
  int? _batteryMinObserved;
  int? _batteryMaxObserved;

  // Network latency sampling (suite-level)
  static const Duration _netSampleInterval = Duration(seconds: 10);
  Timer? _netSampleTimer;
  final List<_LatencySample> _netSamples = <_LatencySample>[];
  int _netProbeAttempts = 0;
  int _netProbeFailures = 0;
  ConnectivityResult? _netConnTypeStart;
  ConnectivityResult? _netConnTypeEnd;
  int _netConnChanges = 0;
  StreamSubscription<List<ConnectivityResult>>? _netConnSub;

  // Optional throughput samples (coarse strength signal)
  static const Duration _netThroughputInterval = Duration(seconds: 20);
  Timer? _netThroughputTimer;
  final List<_ThroughputSample> _netThroughput = <_ThroughputSample>[];

  // ── Design maps ──────────────────────────────────────────────────────────
  static const _testNames = {
    TestId.vmaf: 'Video Experience',
    TestId.peaq: 'Audio Quality',
    TestId.pesq: 'Voice Clarity',
    TestId.iqa: 'Camera Quality',
    TestId.battery: 'Battery Health',
    TestId.network: 'Network',
  };

  static const _testColors = {
    TestId.vmaf: AppTheme.vmafColor,
    TestId.peaq: AppTheme.peaqColor,
    TestId.pesq: AppTheme.pesqColor,
    TestId.iqa: AppTheme.iqaColor,
    TestId.battery: AppTheme.battColor,
    TestId.network: AppTheme.accent,
  };

  static const _testIcons = {
    TestId.vmaf: Icons.videocam_outlined,
    TestId.peaq: Icons.music_note_outlined,
    TestId.pesq: Icons.record_voice_over_outlined,
    TestId.iqa: Icons.image_outlined,
    TestId.battery: Icons.battery_charging_full_outlined,
    TestId.network: Icons.network_check_outlined,
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
    _stopSuiteMonitors();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Orchestration ─────────────────────────────────────────────────────────

  Future<void> _runAll() async {
    _suiteStartedAt = DateTime.now();
    await _startSuiteMonitors();

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

    // Finalize suite-scoped monitors before Results.
    _suiteEndedAt ??= DateTime.now();
    await _finalizeNetworkIfSelected();
    await _finalizeSuiteBatteryIfSelected();
    _stopSuiteMonitors();

    // Network sampling runs in the background; patch the placeholder before Results.
    if (_networkCompleter != null) {
      if (!(_networkCompleter!.isCompleted)) {
        setState(() {
          _overallMsg = 'Finalizing network samples…';
          _progress[TestId.network] = TestProgress(
            testId: TestId.network,
            status: TestStatus.running,
            message: 'Computing latency variance…',
            fraction: 0.90,
          );
        });
      }
      final networkResult = await _networkCompleter!.future;
      final idx = _results.indexWhere((r) => r.id == TestId.network);
      if (idx != -1) _results[idx] = networkResult;
      if (mounted) {
        setState(() {
          _progress[TestId.network] = TestProgress(
            testId: TestId.network,
            status: networkResult.status,
            message: networkResult.status == TestStatus.done
                ? '${_testNames[TestId.network]} complete'
                : 'Failed: ${networkResult.errorMessage}',
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

      case TestId.network:
        // Network runs in background across the entire suite.
        _networkCompleter ??= Completer<TestResult>();
        _emitProgress(
          def.id,
          'Sampling latency every ${_netSampleInterval.inSeconds}s…',
          0.20,
        );
        return TestResult(
          id: def.id,
          status: TestStatus.running,
          scores: const {
            'Status': 'Sampling in background…',
          },
          completedAt: DateTime.now(),
        );
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

  // ── Suite monitors: start/stop/finalize ───────────────────────────────────

  Future<void> _startSuiteMonitors() async {
    // Battery monitor runs only if battery test is selected.
    if (widget.selectedTests.contains(TestId.battery)) {
      await _takeBatteryStartSnapshot();
      _batteryPollTimer?.cancel();
      _batteryPollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
        final level = await _safeBatteryLevel();
        if (level == null || !mounted) return;
        _batteryMinObserved =
            _batteryMinObserved == null ? level : min(_batteryMinObserved!, level);
        _batteryMaxObserved =
            _batteryMaxObserved == null ? level : max(_batteryMaxObserved!, level);
      });
    }

    // Network monitor runs only if network test is selected.
    if (widget.selectedTests.contains(TestId.network)) {
      _netSamples.clear();
      _netThroughput.clear();
      _netProbeAttempts = 0;
      _netProbeFailures = 0;
      _netConnChanges = 0;

      final conn = Connectivity();
      final initial = await conn.checkConnectivity();
      _netConnTypeStart = initial.isNotEmpty ? initial.first : null;
      _netConnTypeEnd = _netConnTypeStart;
      _netConnSub?.cancel();
      _netConnSub = conn.onConnectivityChanged.listen((results) {
        final next = results.isNotEmpty ? results.first : null;
        if (next != _netConnTypeEnd) {
          _netConnChanges++;
        }
        _netConnTypeEnd = next;
      });

      _netSampleTimer?.cancel();
      _netSampleTimer = Timer.periodic(_netSampleInterval, (_) {
        _captureLatencySample();
      });

      // Capture an immediate sample (t=0) so short runs still get data.
      unawaited(_captureLatencySample());

      _netThroughputTimer?.cancel();
      _netThroughputTimer = Timer.periodic(_netThroughputInterval, (_) {
        _captureThroughputSample();
      });
      unawaited(_captureThroughputSample());
    }
  }

  void _stopSuiteMonitors() {
    _batteryPollTimer?.cancel();
    _batteryPollTimer = null;
    _netSampleTimer?.cancel();
    _netSampleTimer = null;
    _netThroughputTimer?.cancel();
    _netThroughputTimer = null;
    _netConnSub?.cancel();
    _netConnSub = null;
  }

  Future<void> _takeBatteryStartSnapshot() async {
    _batteryStartLevel = await _safeBatteryLevel();
    _batteryStartState = await _safeBatteryState();
    if (_batteryStartLevel != null) {
      _batteryMinObserved = _batteryStartLevel;
      _batteryMaxObserved = _batteryStartLevel;
    }
  }

  Future<void> _takeBatteryEndSnapshot() async {
    _batteryEndLevel = await _safeBatteryLevel();
    _batteryEndState = await _safeBatteryState();
  }

  Future<int?> _safeBatteryLevel() async {
    try {
      return await _battery.batteryLevel;
    } catch (_) {
      return null;
    }
  }

  Future<BatteryState?> _safeBatteryState() async {
    try {
      return await _battery.batteryState;
    } catch (_) {
      return null;
    }
  }

  Future<void> _captureLatencySample() async {
    final startedAt = _suiteStartedAt;
    if (startedAt == null) return;
    _netProbeAttempts++;
    final latency = await _measureLatencyMs();
    if (latency == null) return;
    _netSamples.add(_LatencySample(
      t: DateTime.now().difference(startedAt),
      latencyMs: latency,
    ));
  }

  Future<int?> _measureLatencyMs() async {
    try {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(
        '1.1.1.1',
        53,
        timeout: const Duration(seconds: 3),
      );
      sw.stop();
      socket.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      _netProbeFailures++;
      return null;
    }
  }

  Future<void> _captureThroughputSample() async {
    final startedAt = _suiteStartedAt;
    if (startedAt == null) return;
    final mbps = await _measureDownloadMbps();
    if (mbps == null) return;
    _netThroughput.add(_ThroughputSample(
      t: DateTime.now().difference(startedAt),
      mbps: mbps,
    ));
  }

  Future<double?> _measureDownloadMbps() async {
    try {
      final sw = Stopwatch()..start();
      final response = await http
          .get(Uri.parse('https://speed.hetzner.de/1MB.bin'))
          .timeout(const Duration(seconds: 8));
      sw.stop();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final bits = response.bodyBytes.length * 8;
      final seconds = max(sw.elapsedMilliseconds / 1000.0, 0.001);
      return (bits / seconds) / 1000000.0;
    } catch (_) {
      return null;
    }
  }

  Future<void> _finalizeSuiteBatteryIfSelected() async {
    if (!widget.selectedTests.contains(TestId.battery)) {
      return;
    }

    _suiteEndedAt ??= DateTime.now();
    await _takeBatteryEndSnapshot();

    final suiteStart = _suiteStartedAt;
    final suiteEnd = _suiteEndedAt;
    final startLevel = _batteryStartLevel;
    final endLevel = _batteryEndLevel;
    final elapsedMin = (suiteStart != null && suiteEnd != null)
        ? max(suiteEnd.difference(suiteStart).inSeconds / 60.0, 0.001)
        : null;

    final overallDrop =
        (startLevel != null && endLevel != null) ? (startLevel - endLevel) : null;
    final overallDrainRate =
        (overallDrop != null && elapsedMin != null) ? overallDrop / elapsedMin : null;

    final battScore = _batteryScore(overallDrainRate);
    final battInterpretation = _batteryInterpretation(overallDrainRate);
    final battScoreExplain = _batteryScoreExplanation(overallDrainRate);

    // Merge any stress-window metrics already produced by BatteryRunner.
    final stressResultIdx = _results.indexWhere((r) => r.id == TestId.battery);
    final stressScores = stressResultIdx != -1
        ? Map<String, dynamic>.from(_results[stressResultIdx].scores)
        : <String, dynamic>{};

    final mergedScores = <String, dynamic>{
      'What it indicates': battInterpretation,
      'Score (0-100)': battScore,
      'Score method': battScoreExplain,
      'Suite Start': startLevel == null
          ? 'Unknown'
          : '$startLevel% (${_batteryStartState?.name ?? 'unknown'})',
      'Suite End': endLevel == null
          ? 'Unknown'
          : '$endLevel% (${_batteryEndState?.name ?? 'unknown'})',
      'Suite Drop': overallDrop == null ? 'N/A' : '$overallDrop%',
      'Suite Duration': elapsedMin == null ? 'N/A' : '${elapsedMin.toStringAsFixed(1)} min',
      'Suite Drain Score': overallDrainRate == null
          ? 'N/A'
          : '${overallDrainRate.toStringAsFixed(3)} %/min',
      'Min/Max Observed': (_batteryMinObserved == null || _batteryMaxObserved == null)
          ? 'N/A'
          : '${_batteryMinObserved}% / ${_batteryMaxObserved}%',
      ...stressScores,
    };

    final patched = TestResult(
      id: TestId.battery,
      status: TestStatus.done,
      scores: mergedScores,
      completedAt: DateTime.now(),
    );

    if (stressResultIdx != -1) {
      _results[stressResultIdx] = patched;
    }

    await _postBatteryResult(patched, overallDrop, overallDrainRate);
  }

  Future<void> _finalizeNetworkIfSelected() async {
    if (!widget.selectedTests.contains(TestId.network)) {
      return;
    }

    _suiteEndedAt ??= DateTime.now();
    _netSampleTimer?.cancel();
    _netSampleTimer = null;

    final ms = _netSamples.map((e) => e.latencyMs).toList();
    if (ms.isEmpty) {
      final failed = TestResult(
        id: TestId.network,
        status: TestStatus.failed,
        errorMessage: 'No latency samples captured.',
        completedAt: DateTime.now(),
      );
      if (!(_networkCompleter?.isCompleted ?? true)) {
        _networkCompleter!.complete(failed);
      }
      return;
    }

    final mean = ms.reduce((a, b) => a + b) / ms.length;
    final variance = _varianceInt(ms, mean);
    final stddev = sqrt(variance);
    final jitter = _jitter(ms);
    final minLatency = ms.reduce(min);
    final maxLatency = ms.reduce(max);
    final p50 = _percentileInt(ms, 0.50);
    final p95 = _percentileInt(ms, 0.95);
    final lossRate = _netProbeAttempts > 0
        ? (_netProbeFailures / _netProbeAttempts) * 100.0
        : 0.0;

    final mbps = _netThroughput.map((e) => e.mbps).toList();
    final avgMbps =
        mbps.isNotEmpty ? mbps.reduce((a, b) => a + b) / mbps.length : null;
    final stdMbps = mbps.isNotEmpty ? _stdDevDouble(mbps) : null;

    final result = TestResult(
      id: TestId.network,
      status: TestStatus.done,
      scores: {
        'What it indicates': _networkInterpretation(
          p95LatencyMs: p95,
          jitterMs: jitter,
          lossRatePct: lossRate,
        ),
        'Score (0-100)': _networkScore(
          p95LatencyMs: p95,
          jitterMs: jitter,
          lossRatePct: lossRate,
        ),
        'Score method': _networkScoreExplanation(),
        'Samples': ms.length,
        'Interval': '${_netSampleInterval.inSeconds}s',
        'Conn Type (start→end)':
            '${_connLabel(_netConnTypeStart)}→${_connLabel(_netConnTypeEnd)}',
        'Conn Changes': _netConnChanges,
        'Avg Latency': '${mean.toStringAsFixed(1)} ms',
        'Min/Max Latency': '$minLatency / $maxLatency ms',
        'P50/P95 Latency':
            '${p50.toStringAsFixed(0)} / ${p95.toStringAsFixed(0)} ms',
        'Variance': '${variance.toStringAsFixed(1)} ms²',
        'Std Dev': '${stddev.toStringAsFixed(1)} ms',
        'Jitter': '${jitter.toStringAsFixed(1)} ms',
        'Probe Loss': '${lossRate.toStringAsFixed(1)}%',
        if (avgMbps != null) 'Avg Download': '${avgMbps.toStringAsFixed(2)} Mbps',
        if (stdMbps != null)
          'Download Std Dev': '${stdMbps.toStringAsFixed(2)} Mbps',
      },
      completedAt: DateTime.now(),
    );

    if (!(_networkCompleter?.isCompleted ?? true)) {
      _networkCompleter!.complete(result);
    }

    await _postNetworkResult(
      result,
      mean,
      variance,
      stddev,
      jitter,
      minLatency: minLatency.toDouble(),
      maxLatency: maxLatency.toDouble(),
      p50Latency: p50,
      p95Latency: p95,
      lossRatePct: lossRate,
      avgDownloadMbps: avgMbps,
      stdDownloadMbps: stdMbps,
      connTypeStart: _connLabel(_netConnTypeStart),
      connTypeEnd: _connLabel(_netConnTypeEnd),
      connChanges: _netConnChanges,
      probeAttempts: _netProbeAttempts,
      probeFailures: _netProbeFailures,
    );
  }

  double _varianceInt(List<int> values, double mean) {
    final n = values.length;
    if (n == 0) return 0;
    double sum = 0;
    for (final v in values) {
      final d = v - mean;
      sum += d * d;
    }
    return sum / n;
  }

  double _jitter(List<int> values) {
    if (values.length < 2) return 0;
    double sumDiff = 0;
    for (int i = 1; i < values.length; i++) {
      sumDiff += (values[i] - values[i - 1]).abs();
    }
    return sumDiff / (values.length - 1);
  }

  double _stdDevDouble(List<double> values) {
    final mean = values.reduce((a, b) => a + b) / values.length;
    double sum = 0;
    for (final v in values) {
      final d = v - mean;
      sum += d * d;
    }
    return sqrt(sum / values.length);
  }

  double _percentileInt(List<int> values, double p) {
    final sorted = [...values]..sort();
    if (sorted.isEmpty) return 0;
    final idx = (p * (sorted.length - 1)).clamp(0, sorted.length - 1);
    final i = idx.floor();
    final j = idx.ceil();
    if (i == j) return sorted[i].toDouble();
    final t = idx - i;
    return sorted[i].toDouble() + (sorted[j] - sorted[i]) * t;
  }

  String _connLabel(ConnectivityResult? r) {
    if (r == null) return 'unknown';
    return r.name;
  }

  int _batteryScore(double? suiteDrainRatePctPerMin) {
    // Heuristic scale (lower drain is better).
    // Convert to %/hour for easier interpretation.
    if (suiteDrainRatePctPerMin == null) return 0;
    final perHour = suiteDrainRatePctPerMin * 60.0;
    // 100 at <= 2%/hr, 80 at 5%/hr, 50 at 10%/hr, 0 at >= 20%/hr.
    if (perHour <= 2) return 100;
    if (perHour >= 20) return 0;
    // Piecewise linear segments:
    if (perHour <= 5) {
      // 2..5 => 100..80
      final t = (perHour - 2) / 3.0;
      return (100 - 20 * t).round().clamp(0, 100);
    }
    if (perHour <= 10) {
      // 5..10 => 80..50
      final t = (perHour - 5) / 5.0;
      return (80 - 30 * t).round().clamp(0, 100);
    }
    // 10..20 => 50..0
    final t = (perHour - 10) / 10.0;
    return (50 - 50 * t).round().clamp(0, 100);
  }

  String _batteryInterpretation(double? suiteDrainRatePctPerMin) {
    if (suiteDrainRatePctPerMin == null) {
      return 'Battery drain couldn’t be computed reliably (missing start/end level).';
    }
    final perHour = suiteDrainRatePctPerMin * 60.0;
    if (perHour <= 5) {
      return 'Lower drain under the full test suite. Better endurance / efficiency.';
    }
    if (perHour <= 10) {
      return 'Moderate drain during the suite. Expect average endurance under load.';
    }
    return 'High drain during the suite. Indicates weaker endurance under load or high background power use.';
  }

  String _batteryScoreExplanation(double? suiteDrainRatePctPerMin) {
    final perHour = suiteDrainRatePctPerMin == null ? null : suiteDrainRatePctPerMin * 60.0;
    return perHour == null
        ? 'Score=0 when drain rate is unavailable.'
        : 'Uses suite drain rate converted to %/hour. Benchmarks: 100≤2%/hr, 80≈5%/hr, 50≈10%/hr, 0≥20%/hr (piecewise linear).';
  }

  int _networkScore({
    required double p95LatencyMs,
    required double jitterMs,
    required double lossRatePct,
  }) {
    // Score components: latency (60), jitter (25), loss (15).
    // Uses thresholds commonly used for interactive/voice guidance (e.g., ITU-T G.114 one-way delay guidance).
    final lat = _scorePiecewise(p95LatencyMs, [
      const _ScorePoint(80, 60),
      const _ScorePoint(150, 45),
      const _ScorePoint(300, 20),
      const _ScorePoint(600, 0),
    ]);
    final jit = _scorePiecewise(jitterMs, [
      const _ScorePoint(10, 25),
      const _ScorePoint(20, 18),
      const _ScorePoint(50, 8),
      const _ScorePoint(100, 0),
    ]);
    final loss = _scorePiecewise(lossRatePct, [
      const _ScorePoint(0.5, 15),
      const _ScorePoint(1.0, 12),
      const _ScorePoint(2.0, 8),
      const _ScorePoint(5.0, 0),
    ]);
    return (lat + jit + loss).round().clamp(0, 100);
  }

  String _networkInterpretation({
    required double p95LatencyMs,
    required double jitterMs,
    required double lossRatePct,
  }) {
    if (lossRatePct >= 2.0) {
      return 'Packet loss is elevated; expect retries, stalls, and unstable real-time quality.';
    }
    if (p95LatencyMs >= 300 || jitterMs >= 50) {
      return 'Latency/jitter are high; interactive and real-time tasks may feel laggy or choppy.';
    }
    if (p95LatencyMs <= 150 && jitterMs <= 20 && lossRatePct <= 1.0) {
      return 'Stable for interactive use; suitable for most real-time and upload tasks.';
    }
    return 'Usable but variable; expect occasional spikes depending on congestion.';
  }

  String _networkScoreExplanation() {
    return 'Score = latency(60) + jitter(25) + loss(15). Latency uses p95 RTT; jitter uses avg absolute delta; loss is probe timeout rate. Thresholds follow common interactive/voice guidance (see ITU-T G.114 for delay guidance).';
  }

  double _scorePiecewise(double x, List<_ScorePoint> pts) {
    if (pts.isEmpty) return 0;
    if (x <= pts.first.x) return pts.first.score.toDouble();
    for (int i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      if (x <= b.x) {
        final t = (x - a.x) / (b.x - a.x);
        return a.score + (b.score - a.score) * t;
      }
    }
    return pts.last.score.toDouble();
  }

  Future<void> _postBatteryResult(
    TestResult result,
    int? overallDrop,
    double? overallDrainRate,
  ) async {
    final sessionId = SessionStore.instance.sessionId;
    if (sessionId == null) return;

    final payload = <String, dynamic>{
      'suite_started_at': _suiteStartedAt?.toIso8601String(),
      'suite_ended_at': _suiteEndedAt?.toIso8601String(),
      'battery_start_level': _batteryStartLevel,
      'battery_end_level': _batteryEndLevel,
      'battery_start_state': _batteryStartState?.name,
      'battery_end_state': _batteryEndState?.name,
      'overall_drop': overallDrop,
      'overall_drain_rate': overallDrainRate,
      'min_level_observed': _batteryMinObserved,
      'max_level_observed': _batteryMaxObserved,
      'raw_output': result.scores,
    };

    await _postJson(
      path: '/battery/result',
      sessionId: sessionId,
      payload: payload,
    );
  }

  Future<void> _postNetworkResult(
    TestResult result,
    double mean,
    double variance,
    double stddev,
    double jitter,
    {
      double? minLatency,
      double? maxLatency,
      double? p50Latency,
      double? p95Latency,
      double? lossRatePct,
      double? avgDownloadMbps,
      double? stdDownloadMbps,
      String? connTypeStart,
      String? connTypeEnd,
      int? connChanges,
      int? probeAttempts,
      int? probeFailures,
    }
  ) async {
    final sessionId = SessionStore.instance.sessionId;
    if (sessionId == null) return;

    final payload = <String, dynamic>{
      'suite_started_at': _suiteStartedAt?.toIso8601String(),
      'suite_ended_at': _suiteEndedAt?.toIso8601String(),
      'sample_interval_seconds': _netSampleInterval.inSeconds,
      'sample_count': _netSamples.length,
      'avg_latency_ms': mean,
      'variance_latency_ms2': variance,
      'stddev_latency_ms': stddev,
      'jitter_ms': jitter,
      'min_latency_ms': minLatency,
      'max_latency_ms': maxLatency,
      'p50_latency_ms': p50Latency,
      'p95_latency_ms': p95Latency,
      'loss_rate_pct': lossRatePct,
      'avg_download_mbps': avgDownloadMbps,
      'stddev_download_mbps': stdDownloadMbps,
      'conn_type_start': connTypeStart,
      'conn_type_end': connTypeEnd,
      'conn_changes': connChanges,
      'probe_attempts': probeAttempts,
      'probe_failures': probeFailures,
      'samples': _netSamples
          .map((e) => {'t_ms': e.t.inMilliseconds, 'latency_ms': e.latencyMs})
          .toList(),
      'throughput_samples': _netThroughput
          .map((e) => {'t_ms': e.t.inMilliseconds, 'mbps': e.mbps})
          .toList(),
      'raw_output': result.scores,
    };

    await _postJson(
      path: '/network/result',
      sessionId: sessionId,
      payload: payload,
    );
  }

  Future<void> _postJson({
    required String path,
    required String sessionId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}$path'),
            headers: {
              'Content-Type': 'application/json',
              'x-session-id': sessionId,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      // Keep silent; tests should not fail just because telemetry persistence failed.
    }
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

class _LatencySample {
  final Duration t;
  final int latencyMs;
  const _LatencySample({required this.t, required this.latencyMs});
}

class _ThroughputSample {
  final Duration t;
  final double mbps;
  const _ThroughputSample({required this.t, required this.mbps});
}

class _ScorePoint {
  final double x;
  final int score;
  const _ScorePoint(this.x, this.score);
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
