import 'dart:async';
import 'dart:isolate';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:io';

class BatteryLoadPage extends StatefulWidget {
  const BatteryLoadPage({super.key});

  @override
  State<BatteryLoadPage> createState() => _BatteryLoadPageState();
}

class _BatteryLoadPageState extends State<BatteryLoadPage> {
  final Battery _battery = Battery();

  final List<Isolate> _cpuIsolates = <Isolate>[];
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<UserAccelerometerEvent>? _userAccelerometerSubscription;

  Timer? _batteryTimer;
  Timer? _networkTimer;
  StreamSubscription<BatteryState>? _batteryStateSubscription;

  bool _isRunning = false;
  bool _networkLoadEnabled = true;
  bool _sensorLoadEnabled = true;

  int _batteryLevel = 0;
  int? _startBatteryLevel;
  int? _endBatteryLevel;
  BatteryState? _currentBatteryState;
  BatteryState? _startBatteryState;
  BatteryState? _endBatteryState;
  int? _minBatteryLevel;
  int? _maxBatteryLevel;
  DateTime? _testStartedAt;
  DateTime? _testEndedAt;
  String _statusText = 'Idle';

  static void _cpuBurn(dynamic message) {
    while (true) {
      double x = 0;
      for (int i = 0; i < 7000000; i++) {
        x += i * 0.3;
      }
      if (x == -1) {
        break;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _startBatteryMonitor();
    _listenBatteryState();
  }

  Future<void> _startBatteryMonitor() async {
    await _refreshBatteryLevel();
    _batteryTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _refreshBatteryLevel(),
    );
  }

  Future<void> _refreshBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      if (!mounted) {
        return;
      }
      setState(() {
        _batteryLevel = level;
        _minBatteryLevel = _minBatteryLevel == null
            ? level
            : (_minBatteryLevel! < level ? _minBatteryLevel : level);
        _maxBatteryLevel = _maxBatteryLevel == null
            ? level
            : (_maxBatteryLevel! > level ? _maxBatteryLevel : level);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _statusText = 'Unable to read battery level');
    }
  }

  Future<void> _startLoadTest() async {
    if (_isRunning) {
      return;
    }

    setState(() {
      _isRunning = true;
      _statusText = 'Running load test';
      _testStartedAt = DateTime.now();
      _testEndedAt = null;
      _startBatteryLevel = _batteryLevel;
      _endBatteryLevel = null;
      _startBatteryState = _currentBatteryState;
      _endBatteryState = null;
      _minBatteryLevel = _batteryLevel;
      _maxBatteryLevel = _batteryLevel;
    });

    await _startCpuBurn();

    if (_networkLoadEnabled) {
      _startNetworkSpam();
    }

    if (_sensorLoadEnabled) {
      _startSensors();
    }
  }

  Future<void> _startCpuBurn() async {
    final coreCount = Platform.numberOfProcessors;
    final targetIsolates = coreCount > 1 ? coreCount - 1 : 1;

    for (int i = 0; i < targetIsolates; i++) {
      final isolate = await Isolate.spawn(_cpuBurn, null);
      _cpuIsolates.add(isolate);
    }
  }

  void _startNetworkSpam() {
    _networkTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      http.get(Uri.parse('https://speed.hetzner.de/1MB.bin'));
    });
  }

  void _startSensors() {
    _accelerometerSubscription = accelerometerEventStream().listen((_) {});
    _gyroscopeSubscription = gyroscopeEventStream().listen((_) {});
    _userAccelerometerSubscription =
        userAccelerometerEventStream().listen((_) {});
  }

  void _stopLoadTest() {
    for (final isolate in _cpuIsolates) {
      isolate.kill(priority: Isolate.immediate);
    }
    _cpuIsolates.clear();

    _networkTimer?.cancel();
    _networkTimer = null;

    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _userAccelerometerSubscription?.cancel();

    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
    _userAccelerometerSubscription = null;

    if (!mounted) {
      return;
    }
    final now = DateTime.now();
    final endLevel = _batteryLevel;
    final elapsedMinutes = _testStartedAt == null
        ? null
        : now.difference(_testStartedAt!).inSeconds / 60.0;
    final drop = (_startBatteryLevel != null) ? _startBatteryLevel! - endLevel : null;
    final rate = (drop != null && elapsedMinutes != null && elapsedMinutes > 0)
        ? drop / elapsedMinutes
        : null;
    setState(() {
      _isRunning = false;
      _testEndedAt = now;
      _endBatteryLevel = endLevel;
      _endBatteryState = _currentBatteryState;
      _statusText = drop == null
          ? 'Stopped'
          : 'Stopped. Drain: $drop% in ${elapsedMinutes?.toStringAsFixed(2) ?? 'N/A'} min '
              '(${rate?.toStringAsFixed(3) ?? 'N/A'} %/min)';
    });
  }

  void _listenBatteryState() {
    _batteryStateSubscription = _battery.onBatteryStateChanged.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() => _currentBatteryState = state);
    });
  }

  String _batterySummaryText() {
    if (_testStartedAt == null || _endBatteryLevel == null || _startBatteryLevel == null) {
      return 'Run a test to compute drain score and battery analytics.';
    }
    final elapsedMinutes = _testEndedAt == null
        ? DateTime.now().difference(_testStartedAt!).inSeconds / 60.0
        : _testEndedAt!.difference(_testStartedAt!).inSeconds / 60.0;
    final drop = _startBatteryLevel! - _endBatteryLevel!;
    final drainPerMinute = elapsedMinutes > 0 ? drop / elapsedMinutes : 0.0;
    return 'Start: $_startBatteryLevel% (${_startBatteryState?.name ?? 'unknown'})  '
        'End: $_endBatteryLevel% (${_endBatteryState?.name ?? 'unknown'})\n'
        'Drop: $drop%  Duration: ${elapsedMinutes.toStringAsFixed(2)} min  '
        'Drain score: ${drainPerMinute.toStringAsFixed(3)} %/min\n'
        'Min/Max observed: ${_minBatteryLevel ?? '-'}% / ${_maxBatteryLevel ?? '-'}%';
  }

  @override
  void dispose() {
    _stopLoadTest();
    _batteryTimer?.cancel();
    _batteryStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                    'Battery Load Tester',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Stress CPU/network/sensors and monitor battery drain while pinging your Python backend.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('Battery: $_batteryLevel%')),
                      Chip(
                        label: Text(
                          'State: ${_currentBatteryState?.name ?? 'unknown'}',
                        ),
                      ),
                      Chip(
                        label: Text(
                          _isRunning ? 'Status: Running' : 'Status: Stopped',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_statusText),
                  const SizedBox(height: 8),
                  Text(_batterySummaryText()),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SwitchListTile(
                    value: _networkLoadEnabled,
                    onChanged: _isRunning
                        ? null
                        : (value) {
                            setState(() => _networkLoadEnabled = value);
                          },
                    title: const Text('Network load'),
                    subtitle: const Text('Repeated HTTP downloads'),
                  ),
                  SwitchListTile(
                    value: _sensorLoadEnabled,
                    onChanged: _isRunning
                        ? null
                        : (value) {
                            setState(() => _sensorLoadEnabled = value);
                          },
                    title: const Text('Sensor listeners'),
                    subtitle: const Text('Accelerometer + gyroscope streams'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isRunning ? null : _startLoadTest,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Load Test'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isRunning ? _stopLoadTest : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
