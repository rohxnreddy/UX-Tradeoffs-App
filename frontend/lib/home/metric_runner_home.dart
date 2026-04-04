import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class MetricRunnerHome extends StatefulWidget {
  const MetricRunnerHome({super.key});

  @override
  State<MetricRunnerHome> createState() => _MetricRunnerHomeState();
}

class _MetricRunnerHomeState extends State<MetricRunnerHome> {
  final Battery _battery = Battery();
  static const String _defaultApiBaseUrl = 'http://192.168.0.100:8000';

  final List<_StepResult> _results = <_StepResult>[];
  final List<_StepResult> _workingResults = <_StepResult>[];
  final List<Isolate> _cpuIsolates = <Isolate>[];
  final List<int> _latencySamples = <int>[];
  final List<double> _downloadMbpsSamples = <double>[];

  Timer? _backgroundLoadTimer;
  bool _isRunning = false;
  int? _startBattery;
  int? _endBattery;
  BatteryState? _startBatteryState;
  BatteryState? _endBatteryState;
  String _progressText = 'Ready';
  DateTime? _runStartedAt;
  DateTime? _runEndedAt;

  static void _cpuBurn(dynamic _) {
    while (true) {
      double v = 0;
      for (int i = 0; i < 8000000; i++) {
        v += i * 0.11;
      }
      if (v == -1) {
        break;
      }
    }
  }

  Future<void> _runAllTests() async {
    if (_isRunning) {
      return;
    }

    setState(() {
      _isRunning = true;
      _results.clear();
      _workingResults.clear();
      _latencySamples.clear();
      _downloadMbpsSamples.clear();
      _runStartedAt = DateTime.now();
      _runEndedAt = null;
      _progressText = 'Starting test suite...';
    });

    try {
      _startBattery = await _safeBatteryLevel();
      _startBatteryState = await _safeBatteryState();
      _addWorkingResult(
        _StepResult.pass(
          title: 'Initial battery snapshot',
          detail: 'Battery at start: ${_startBattery ?? 'Unknown'}% '
              '(state: ${_startBatteryState?.name ?? 'unknown'})',
        ),
      );

      await _runStep(
        title: 'Backend reachability',
        action: _testBackend,
      );
      await _runStep(
        title: 'Network strength and quality',
        action: _testNetworkStrengthAndFluctuation,
      );
      await _runStep(
        title: 'Background battery load window',
        action: _testBackgroundBatteryLoad,
      );
      await _runStep(
        title: 'Deferred foreground checks',
        action: _runDeferredForegroundChecks,
      );

      _endBattery = await _safeBatteryLevel();
      _endBatteryState = await _safeBatteryState();
      _runEndedAt = DateTime.now();
      final delta = (_startBattery != null && _endBattery != null)
          ? (_startBattery! - _endBattery!)
          : null;
      final elapsedMinutes = (_runStartedAt != null && _runEndedAt != null)
          ? _runEndedAt!.difference(_runStartedAt!).inSeconds / 60.0
          : null;
      final drainPerMinute =
          (delta != null && elapsedMinutes != null && elapsedMinutes > 0)
              ? delta / elapsedMinutes
              : null;
      _addWorkingResult(
        _StepResult.pass(
          title: 'Final battery snapshot',
          detail: delta == null
              ? 'End battery: ${_endBattery ?? 'Unknown'}% '
                  '(state: ${_endBatteryState?.name ?? 'unknown'})'
              : 'End battery: $_endBattery% (drain: $delta%, '
                  'drain rate: ${drainPerMinute?.toStringAsFixed(3) ?? 'N/A'} %/min, '
                  'state: ${_endBatteryState?.name ?? 'unknown'})',
        ),
      );
      _addWorkingResult(
        _StepResult.pass(
          title: 'Battery score',
          detail: drainPerMinute == null
              ? 'Score unavailable (insufficient timing/battery data).'
              : 'Battery drain score: ${drainPerMinute.toStringAsFixed(3)} %/min '
                  '(lower is better).',
        ),
      );
    } catch (e) {
      _addWorkingResult(
        _StepResult.fail(
          title: 'Runner failure',
          detail: e.toString(),
        ),
      );
    } finally {
      _stopBackgroundLoad();
      _runEndedAt ??= DateTime.now();
      _progressText = 'Test suite completed';
      _results
        ..clear()
        ..addAll(_workingResults);
      await _persistResults();
      if (mounted) {
        setState(() => _isRunning = false);
      }
    }
  }

  Future<void> _runStep({
    required String title,
    required Future<String> Function() action,
  }) async {
    setState(() => _progressText = 'Running: $title');
    try {
      final detail = await action();
      _addWorkingResult(_StepResult.pass(title: title, detail: detail));
    } catch (e) {
      _addWorkingResult(_StepResult.fail(title: title, detail: e.toString()));
    }
  }

  Future<String> _testBackend() async {
    final base = _defaultApiBaseUrl;
    final root = await http
        .get(Uri.parse('$base/'))
        .timeout(const Duration(seconds: 5));
    final peaq = await http
        .get(Uri.parse('$base/audio/peaq'))
        .timeout(const Duration(seconds: 10));
    final pesq = await http
        .get(Uri.parse('$base/audio/pesq'))
        .timeout(const Duration(seconds: 10));

    final okRoot = root.statusCode >= 200 && root.statusCode < 300;
    final okPeaq = peaq.statusCode >= 200 && peaq.statusCode < 300;
    final okPesq = pesq.statusCode >= 200 && pesq.statusCode < 300;
    if (!okRoot) {
      throw Exception('Backend root failed: HTTP ${root.statusCode}');
    }

    return 'Root OK (${root.statusCode}), /audio/peaq ${peaq.statusCode}, /audio/pesq ${pesq.statusCode}.';
  }

  Future<String> _testNetworkStrengthAndFluctuation() async {
    _latencySamples.clear();
    _downloadMbpsSamples.clear();
    final connectivity = Connectivity();
    final changes = <String>[];
    final sub = connectivity.onConnectivityChanged.listen((event) {
      changes.add(event.map((e) => e.name).join(','));
    });

    try {
      for (int i = 0; i < 6; i++) {
        final latency = await _measureLatencyMs();
        if (latency != null) {
          _latencySamples.add(latency);
        }
        final mbps = await _measureDownloadMbps();
        if (mbps != null) {
          _downloadMbpsSamples.add(mbps);
        }
        await Future.delayed(const Duration(milliseconds: 450));
      }
    } finally {
      await sub.cancel();
    }

    if (_latencySamples.isEmpty || _downloadMbpsSamples.isEmpty) {
      throw Exception('Network test could not capture enough samples.');
    }

    final avgLatency =
        _latencySamples.reduce((a, b) => a + b) / _latencySamples.length;
    final latencyStdDev = _stdDevInt(_latencySamples);
    final avgMbps = _downloadMbpsSamples.reduce((a, b) => a + b) /
        _downloadMbpsSamples.length;
    final speedVariance = _stdDevDouble(_downloadMbpsSamples);
    final jitter = _jitter(_latencySamples);

    final quality = _networkQuality(avgLatency, avgMbps);
    final fluctuation = _fluctuationComment(latencyStdDev, speedVariance, jitter);
    final handovers = changes.length;

    return 'Quality: $quality. Avg latency: ${avgLatency.toStringAsFixed(1)} ms, '
        'avg speed: ${avgMbps.toStringAsFixed(2)} Mbps, jitter: ${jitter.toStringAsFixed(1)} ms. '
        'Fluctuation: $fluctuation. Connectivity changes observed: $handovers.';
  }

  Future<String> _testBackgroundBatteryLoad() async {
    final cores = Platform.numberOfProcessors;
    final target = cores > 2 ? 2 : 1;
    for (int i = 0; i < target; i++) {
      final isolate = await Isolate.spawn(_cpuBurn, null);
      _cpuIsolates.add(isolate);
    }

    _backgroundLoadTimer = Timer.periodic(
      const Duration(milliseconds: 350),
      (_) {
        http.get(Uri.parse('https://speed.hetzner.de/1MB.bin'));
      },
    );

    await Future.delayed(const Duration(seconds: 12));
    _stopBackgroundLoad();
    return 'Ran mixed CPU + network load for 12 seconds in background.';
  }

  Future<String> _runDeferredForegroundChecks() async {
    final batteryNow = await _safeBatteryLevel();
    final quickLatency = await _measureLatencyMs();
    return 'Foreground finalization complete. Battery now: ${batteryNow ?? 'Unknown'}%, '
        'instant latency: ${quickLatency ?? 'N/A'} ms. Manual media tests (VMAF/PEAQ/PESQ/IQA) remain available in their pages.';
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
      return null;
    }
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

  void _stopBackgroundLoad() {
    _backgroundLoadTimer?.cancel();
    _backgroundLoadTimer = null;
    for (final isolate in _cpuIsolates) {
      isolate.kill(priority: Isolate.immediate);
    }
    _cpuIsolates.clear();
  }

  String _networkQuality(double avgLatency, double avgMbps) {
    if (avgLatency < 90 && avgMbps > 20) {
      return 'Strong';
    }
    if (avgLatency < 180 && avgMbps > 5) {
      return 'Moderate';
    }
    return 'Weak';
  }

  String _fluctuationComment(double latencyStd, double speedStd, double jitter) {
    if (latencyStd < 20 && speedStd < 1.5 && jitter < 20) {
      return 'Stable network, low fluctuation';
    }
    if (latencyStd < 50 && speedStd < 4 && jitter < 45) {
      return 'Mild fluctuation, acceptable for most tests';
    }
    return 'High fluctuation detected; run quality tests multiple times';
  }

  double _stdDevInt(List<int> values) {
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) /
            values.length;
    return sqrt(variance.toDouble());
  }

  double _stdDevDouble(List<double> values) {
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) /
            values.length;
    return sqrt(variance.toDouble());
  }

  double _jitter(List<int> values) {
    if (values.length < 2) {
      return 0;
    }
    double sumDiff = 0;
    for (int i = 1; i < values.length; i++) {
      sumDiff += (values[i] - values[i - 1]).abs();
    }
    return sumDiff / (values.length - 1);
  }

  void _addWorkingResult(_StepResult result) {
    _workingResults.add(result);
  }

  Future<void> _persistResults() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'started_at': _runStartedAt?.toIso8601String(),
      'ended_at': _runEndedAt?.toIso8601String(),
      'battery_start': _startBattery,
      'battery_end': _endBattery,
      'battery_start_state': _startBatteryState?.name,
      'battery_end_state': _endBatteryState?.name,
      'elapsed_seconds': _runStartedAt != null && _runEndedAt != null
          ? _runEndedAt!.difference(_runStartedAt!).inSeconds
          : null,
      'results': _results
          .map((e) => {'title': e.title, 'ok': e.ok, 'detail': e.detail})
          .toList(),
    };
    await prefs.setString('latest_metric_test_run', jsonEncode(payload));
  }

  @override
  void dispose() {
    _stopBackgroundLoad();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runCompleted = !_isRunning && _results.isNotEmpty;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Automated Metric Runner',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Runs backend, network quality, and battery load checks in sequence. '
                      'Background-safe tasks run concurrently where possible.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _isRunning ? null : _runAllTests,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(_isRunning ? 'Running...' : 'Run Metric Tests'),
                    ),
                    const SizedBox(height: 8),
                    Text('Status: $_progressText'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isRunning)
              Card(
                color: Colors.amber.shade50,
                child: const ListTile(
                  leading: Icon(Icons.hourglass_top),
                  title: Text('Tests are running sequentially'),
                  subtitle: Text(
                    'Results will be shown here after all tests complete.',
                  ),
                ),
              ),
            if (_results.isNotEmpty && !_isRunning)
              ..._results.map(
                (r) => Card(
                  child: ListTile(
                    leading: Icon(
                      r.ok ? Icons.check_circle : Icons.error_outline,
                      color: r.ok ? Colors.green : Colors.red,
                    ),
                    title: Text(r.title),
                    subtitle: Text(r.detail),
                  ),
                ),
              ),
            if (runCompleted) ...[
              const SizedBox(height: 8),
              Card(
                color: Colors.blue.shade50,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Disclaimer: Network quality results are location dependent and can vary with '
                    'distance to towers/routers, local congestion, and physical surroundings.',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepResult {
  final String title;
  final bool ok;
  final String detail;

  const _StepResult({
    required this.title,
    required this.ok,
    required this.detail,
  });

  factory _StepResult.pass({required String title, required String detail}) {
    return _StepResult(title: title, ok: true, detail: detail);
  }

  factory _StepResult.fail({required String title, required String detail}) {
    return _StepResult(title: title, ok: false, detail: detail);
  }
}
