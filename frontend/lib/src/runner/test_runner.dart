// lib/src/runner/test_runner.dart
//
// ARCHITECTURE NOTE
// ─────────────────
// Tests that require hardware interaction (camera, microphone, screen recording)
// CANNOT run silently in the background.  They each need their own full-screen
// UI page.  The orchestrator (RunningScreen) navigates to each test page in
// sequence and waits for it to return a TestResult before moving on.
//
// This file therefore only contains:
//   • TestProgress model (used by RunningScreen for the progress list)
//   • BatteryRunner  (the one test that genuinely runs in-process)
//
// VMAF  → VmafTestPage   (screen recording + video player)
// PEAQ  → PeaqTestPage   (mic + speaker + audio player)
// PESQ  → PesqTestPage   (mic + speaker + audio player)
// IQA   → IqaTestPage    (camera capture + image upload)
// Battery → BatteryRunner (CPU/network stress, no UI needed)

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:battery_plus/battery_plus.dart';
import 'package:http/http.dart' as http;

import 'test_model.dart';

// ── Progress model ────────────────────────────────────────────────────────────

class TestProgress {
  final TestId testId;
  final TestStatus status;
  final String message;
  final double fraction; // 0..1

  const TestProgress({
    required this.testId,
    required this.status,
    required this.message,
    required this.fraction,
  });
}

typedef ProgressCallback = void Function(TestProgress p);

// ── Battery runner (in-process, no UI) ───────────────────────────────────────

class BatteryRunner {
  final ProgressCallback onProgress;
  BatteryRunner({required this.onProgress});

  void _emit(String msg, double frac) => onProgress(
    TestProgress(
      testId: TestId.battery,
      status: TestStatus.running,
      message: msg,
      fraction: frac,
    ),
  );

  Future<TestResult> run() async {
    final battery = Battery();
    final isolates = <Isolate>[];

    _emit('Taking battery snapshot…', 0.05);
    final startLevel = await battery.batteryLevel;
    final startState = await battery.batteryState;
    final startTime = DateTime.now();

    _emit('Starting CPU + network stress…', 0.10);
    final cores = Platform.numberOfProcessors;
    final target = cores > 2 ? 2 : 1;
    for (int i = 0; i < target; i++) {
      isolates.add(await Isolate.spawn(_cpuBurn, null));
    }

    Timer? netTimer;
    netTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      http
          .get(Uri.parse('https://speed.hetzner.de/1MB.bin'))
          .catchError((_) => http.Response('', 599));
    });

    const totalSeconds = 45;
    const stepSeconds = 5;
    const steps = totalSeconds ~/ stepSeconds;

    for (int i = 0; i < steps; i++) {
      await Future.delayed(const Duration(seconds: stepSeconds));
      _emit(
        'Stress running… ${(i + 1) * stepSeconds}s / ${totalSeconds}s',
        0.10 + 0.80 * ((i + 1) / steps),
      );
    }

    netTimer.cancel();
    for (final iso in isolates) iso.kill(priority: Isolate.immediate);

    _emit('Computing drain score…', 0.95);
    final endLevel = await battery.batteryLevel;
    final endState = await battery.batteryState;
    final elapsed = DateTime.now().difference(startTime).inSeconds / 60.0;
    final drop = startLevel - endLevel;
    final drainRate = elapsed > 0 ? drop / elapsed : 0.0;

    return TestResult(
      id: TestId.battery,
      status: TestStatus.done,
      scores: {
        'Start Level': '$startLevel% (${startState.name})',
        'End Level': '$endLevel% (${endState.name})',
        'Drain': '$drop%',
        'Duration': '${elapsed.toStringAsFixed(1)} min',
        'Drain Score': '${drainRate.toStringAsFixed(3)} %/min',
      },
      completedAt: DateTime.now(),
    );
  }

  static void _cpuBurn(dynamic _) {
    while (true) {
      double x = 0;
      for (int i = 0; i < 7_000_000; i++) x += i * 0.3;
      if (x == -1) break;
    }
  }
}
