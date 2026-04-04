// lib/src/runner/test_runner.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/app_config.dart';
import '../core/session_store.dart';
import '../services/speaker_control.dart';
import 'test_model.dart';

// ── Progress update ───────────────────────────────────────────────────────────

class TestProgress {
  final TestId         testId;
  final TestStatus     status;
  final String         message;
  final double         fraction; // 0..1 within this test

  const TestProgress({
    required this.testId,
    required this.status,
    required this.message,
    required this.fraction,
  });
}

// ── Runner ────────────────────────────────────────────────────────────────────

typedef ProgressCallback = void Function(TestProgress p);

class TestRunner {
  final ProgressCallback onProgress;
  final List<TestId>     selectedTests;

  TestRunner({required this.onProgress, required this.selectedTests});

  String get _base => AppConfig.apiBaseUrl;
  String? get _sessionId => SessionStore.instance.sessionId;

  /// Run all selected tests sequentially. Returns a list of results.
  Future<List<TestResult>> run() async {
    final results = <TestResult>[];
    for (final def in allTests) {
      if (!selectedTests.contains(def.id)) {
        results.add(TestResult(id: def.id, status: TestStatus.skipped));
        continue;
      }
      _emit(def.id, TestStatus.running, 'Starting ${def.title}…', 0.0);
      try {
        final scores = await _runOne(def);
        results.add(TestResult(
          id:          def.id,
          status:      TestStatus.done,
          scores:      scores,
          completedAt: DateTime.now(),
        ));
        _emit(def.id, TestStatus.done, '${def.title} complete', 1.0);
      } catch (e) {
        results.add(TestResult(
          id:           def.id,
          status:       TestStatus.failed,
          errorMessage: e.toString(),
          completedAt:  DateTime.now(),
        ));
        _emit(def.id, TestStatus.failed, 'Failed: $e', 1.0);
      }
    }
    return results;
  }

  void _emit(TestId id, TestStatus st, String msg, double frac) {
    onProgress(TestProgress(testId: id, status: st, message: msg, fraction: frac));
  }

  // ── Dispatcher ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _runOne(TestDefinition def) {
    switch (def.id) {
      case TestId.vmaf:    return _runVmaf();
      case TestId.peaq:    return _runPeaq();
      case TestId.pesq:    return _runPesq();
      case TestId.iqa:     return _runIqa();
      case TestId.battery: return _runBattery();
    }
  }

  // ── VMAF ────────────────────────────────────────────────────────────────────
  // NOTE: VMAF requires screen recording which must be triggered from UI.
  // In the runner mode the page handles it; here we just POST a dummy ping
  // and return whatever the server already computed (session-based).
  // In practice the VMAF widget is run first with its own UI, and the runner
  // just fetches the last result for that session.
  Future<Map<String, dynamic>> _runVmaf() async {
    _emit(TestId.vmaf, TestStatus.running, 'Fetching VMAF session result…', 0.5);
    final sid = _sessionId;
    if (sid == null) throw Exception('No active session');
    final res = await http
        .get(Uri.parse('$_base/vmaf/latest?session_id=$sid'))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final score = (data['vmaf_score'] as num?)?.toDouble();
      return {'VMAF Score': score?.toStringAsFixed(2) ?? 'N/A'};
    }
    throw Exception('VMAF fetch failed (${res.statusCode})');
  }

  // ── PEAQ ────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _runPeaq() async {
    final recorder = AudioRecorder();
    final refPlayer = AudioPlayer();
    final tempDir   = await getTemporaryDirectory();
    try {
      if (!await recorder.hasPermission()) throw Exception('Microphone permission denied');

      // 1. Record room noise (3 s)
      _emit(TestId.peaq, TestStatus.running, 'Recording room noise (3s)…', 0.1);
      final noisePath    = '${tempDir.path}/peaq_noise.wav';
      final degradedPath = '${tempDir.path}/peaq_degraded.wav';
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 44100,
            numChannels: 1, echoCancel: false, noiseSuppress: false, autoGain: false,
            androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.camcorder)),
        path: noisePath,
      );
      await Future.delayed(const Duration(seconds: 3));
      await recorder.stop();

      // 2. Download reference
      _emit(TestId.peaq, TestStatus.running, 'Downloading reference audio…', 0.3);
      final audioRes = await http.get(Uri.parse('$_base/audio/peaq'))
          .timeout(const Duration(seconds: 30));
      if (audioRes.statusCode != 200) throw Exception('Reference download failed');
      final refPath = '${tempDir.path}/peaq_reference.wav';
      await File(refPath).writeAsBytes(audioRes.bodyBytes);

      // 3. Play & record
      _emit(TestId.peaq, TestStatus.running, 'Playing reference & recording…', 0.5);
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 44100,
            numChannels: 1, echoCancel: false, noiseSuppress: false, autoGain: false,
            androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.camcorder)),
        path: degradedPath,
      );
      await Future.delayed(const Duration(milliseconds: 300));
      await SpeakerControl.enableSpeaker();
      await refPlayer.setFilePath(refPath);
      await refPlayer.setVolume(1.0);
      await refPlayer.play();
      await refPlayer.playerStateStream
          .firstWhere((s) => s.processingState == ProcessingState.completed);
      await Future.delayed(const Duration(milliseconds: 500));
      await recorder.stop();
      await SpeakerControl.disableSpeaker();

      // 4. Upload
      _emit(TestId.peaq, TestStatus.running, 'Uploading for analysis…', 0.75);
      final req = http.MultipartRequest('POST', Uri.parse('$_base/peaq/score'));
      req.files.add(await http.MultipartFile.fromPath('degraded_audio', degradedPath));
      req.files.add(await http.MultipartFile.fromPath('room_noise',     noisePath));
      if (_sessionId != null) req.headers['x-session-id'] = _sessionId!;
      final streamed = await req.send().timeout(const Duration(minutes: 2));
      final body     = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) throw Exception('PEAQ server error (${streamed.statusCode})');
      final data = jsonDecode(body) as Map<String, dynamic>;
      final odg  = (data['odg_score'] as num?)?.toDouble();
      final raw  = (data['raw_odg']   as num?)?.toDouble();
      return {
        'ODG Score':    odg?.toStringAsFixed(2)  ?? 'N/A',
        'Raw ODG':      raw?.toStringAsFixed(2)  ?? 'N/A',
      };
    } finally {
      recorder.dispose();
      refPlayer.dispose();
    }
  }

  // ── PESQ ────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _runPesq() async {
    final recorder = AudioRecorder();
    final refPlayer = AudioPlayer();
    final tempDir   = await getTemporaryDirectory();
    try {
      if (!await recorder.hasPermission()) throw Exception('Microphone permission denied');

      // 1. Download reference
      _emit(TestId.pesq, TestStatus.running, 'Downloading reference speech…', 0.1);
      final audioRes = await http.get(Uri.parse('$_base/audio/pesq'))
          .timeout(const Duration(seconds: 30));
      if (audioRes.statusCode != 200) throw Exception('PESQ reference download failed');
      final refPath = '${tempDir.path}/pesq_ref.wav';
      await File(refPath).writeAsBytes(audioRes.bodyBytes);

      // 2. Record
      _emit(TestId.pesq, TestStatus.running, 'Playing & recording WebRTC speech…', 0.35);
      final recordPath = '${tempDir.path}/pesq_recording.wav';
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000,
            numChannels: 1, echoCancel: false, noiseSuppress: false, autoGain: false,
            androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.camcorder)),
        path: recordPath,
      );
      await Future.delayed(const Duration(milliseconds: 300));
      await SpeakerControl.enableSpeaker();
      await refPlayer.setFilePath(refPath);
      await refPlayer.setVolume(1.0);
      await refPlayer.play();
      await refPlayer.playerStateStream
          .firstWhere((s) => s.processingState == ProcessingState.completed);
      await Future.delayed(const Duration(milliseconds: 500));
      await recorder.stop();
      await SpeakerControl.disableSpeaker();

      // 3. Upload
      _emit(TestId.pesq, TestStatus.running, 'Processing through WebRTC codecs…', 0.65);
      final req = http.MultipartRequest('POST', Uri.parse('$_base/webrtc/device-call'));
      req.files.add(await http.MultipartFile.fromPath('recorded_audio', recordPath,
          filename: 'webrtc_recording.wav'));
      if (_sessionId != null) req.headers['x-session-id'] = _sessionId!;
      final streamed = await req.send().timeout(const Duration(minutes: 2));
      final body     = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) throw Exception('PESQ server error (${streamed.statusCode})');
      final data    = jsonDecode(body) as Map<String, dynamic>;
      final voip    = (data['voip_wideband']?['pesq_score']         as num?)?.toDouble();
      final trad    = (data['traditional_narrowband']?['pesq_score'] as num?)?.toDouble();
      final volte   = (data['volte_wideband']?['pesq_score']         as num?)?.toDouble();
      final direct  = (data['direct_recording']?['pesq_score']       as num?)?.toDouble();
      return {
        'PSTN (G.711)':  trad?.toStringAsFixed(2)   ?? 'N/A',
        'VoIP (Opus)':   voip?.toStringAsFixed(2)   ?? 'N/A',
        'VoLTE (AMR-WB)':volte?.toStringAsFixed(2)  ?? 'N/A',
        'Device Score':  direct?.toStringAsFixed(2) ?? 'N/A',
      };
    } finally {
      recorder.dispose();
      refPlayer.dispose();
    }
  }

  // ── IQA ─────────────────────────────────────────────────────────────────────
  // In automated mode we cannot take a camera photo without UI.
  // We call the endpoint with an empty multipart to signal "automated" or
  // let the server return the last captured result for this session.
  Future<Map<String, dynamic>> _runIqa() async {
    _emit(TestId.iqa, TestStatus.running, 'Fetching IQA session result…', 0.5);
    final sid = _sessionId;
    if (sid == null) throw Exception('No active session');
    final res = await http
        .get(Uri.parse('$_base/iqa/latest?session_id=$sid'))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) {
      final data    = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (data['results'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (results.isEmpty) throw Exception('No IQA data for this session');
      final first = results.first;
      return {
        'BRISQUE': (first['brisque'] as num?)?.toStringAsFixed(2) ?? 'N/A',
        'NIQE':    (first['niqe']    as num?)?.toStringAsFixed(2) ?? 'N/A',
        'PIQE':    (first['piqe']    as num?)?.toStringAsFixed(2) ?? 'N/A',
      };
    }
    throw Exception('IQA fetch failed (${res.statusCode})');
  }

  // ── Battery ──────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _runBattery() async {
    final battery = Battery();
    final isolates = <Isolate>[];

    _emit(TestId.battery, TestStatus.running, 'Taking battery snapshot…', 0.05);
    final startLevel = await battery.batteryLevel;
    final startState = await battery.batteryState;
    final startTime  = DateTime.now();

    // Spawn CPU burners
    _emit(TestId.battery, TestStatus.running, 'Starting CPU + network stress…', 0.1);
    final cores  = Platform.numberOfProcessors;
    final target = cores > 2 ? 2 : 1;
    for (int i = 0; i < target; i++) {
      final iso = await Isolate.spawn(_cpuBurn, null);
      isolates.add(iso);
    }

    // Network spam
    Timer? netTimer;
    netTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      http.get(Uri.parse('https://speed.hetzner.de/1MB.bin'));
    });

    // Run for 45 seconds
    for (int i = 0; i < 9; i++) {
      await Future.delayed(const Duration(seconds: 5));
      _emit(TestId.battery, TestStatus.running,
          'Stress running… ${(i + 1) * 5}s / 45s', 0.1 + 0.8 * ((i + 1) / 9));
    }

    netTimer.cancel();
    for (final iso in isolates) iso.kill(priority: Isolate.immediate);

    _emit(TestId.battery, TestStatus.running, 'Computing drain score…', 0.95);
    final endLevel   = await battery.batteryLevel;
    final endState   = await battery.batteryState;
    final elapsed    = DateTime.now().difference(startTime).inSeconds / 60.0;
    final drop       = startLevel - endLevel;
    final drainScore = elapsed > 0 ? drop / elapsed : 0.0;

    return {
      'Start Level':  '$startLevel% (${startState.name})',
      'End Level':    '$endLevel% (${endState.name})',
      'Drain':        '$drop%',
      'Duration':     '${elapsed.toStringAsFixed(1)} min',
      'Drain Score':  '${drainScore.toStringAsFixed(3)} %/min',
    };
  }

  static void _cpuBurn(dynamic _) {
    while (true) {
      double x = 0;
      for (int i = 0; i < 7000000; i++) x += i * 0.3;
      if (x == -1) break;
    }
  }
}
