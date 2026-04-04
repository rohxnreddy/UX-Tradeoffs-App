// lib/src/tests/pesq_test_page.dart
//
// PESQ test page — voice clarity via WebRTC simulator.
// Flow:
//   1. Record 3 s of room noise.
//   2. Download reference speech from /audio/pesq.
//   3. Play reference through speaker while recording.
//   4. Upload both WAVs to POST /pesq/score.
//   5. Pop with TestResult.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/app_config.dart';
import '../core/session_store.dart';
import '../core/theme.dart';
import '../runner/test_model.dart';
import '../services/speaker_control.dart';

class PesqTestPage extends StatefulWidget {
  final void Function(String message, double fraction) onProgressUpdate;

  const PesqTestPage({super.key, required this.onProgressUpdate});

  @override
  State<PesqTestPage> createState() => _PesqTestPageState();
}

class _PesqTestPageState extends State<PesqTestPage>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder  = AudioRecorder();
  final AudioPlayer   _refPlayer = AudioPlayer();

  bool    _isProcessing = false;
  bool    _autoStarted  = false;
  String  _statusMsg    = 'Initialising…';
  String? _errorMsg;

  late AnimationController _pulseCtrl;

  String  get _apiBase   => AppConfig.apiBaseUrl;
  String? get _sessionId => SessionStore.instance.sessionId;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_autoStarted) { _autoStarted = true; _runTest(); }
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _recorder.dispose();
    _refPlayer.dispose();
    super.dispose();
  }

  Future<void> _runTest() async {
    setState(() { _isProcessing = true; _errorMsg = null; });

    try {
      _update('Checking microphone access…', 0.02);
      if (!await _recorder.hasPermission()) {
        throw Exception('Microphone access is required.');
      }

      final tmpDir       = await getTemporaryDirectory();
      final noisePath    = '${tmpDir.path}/pesq_noise.wav';
      final degradedPath = '${tmpDir.path}/pesq_degraded.wav';

      _update('Listening to the room for 3 seconds…', 0.10);
      await _recorder.start(
        const RecordConfig(
          encoder:            AudioEncoder.wav,
          sampleRate:         16000,
          numChannels:        1,
          echoCancel:         false,
          noiseSuppress:      false,
          autoGain:           false,
          androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.mic),
        ),
        path: noisePath,
      );
      await Future.delayed(const Duration(seconds: 3));
      await _recorder.stop();

      _update('Downloading voice sample…', 0.30);
      final audioRes = await http.get(Uri.parse('$_apiBase/audio/pesq'));
      if (audioRes.statusCode != 200) throw Exception('Download failed');
      final refPath = '${tmpDir.path}/pesq_reference.wav';
      await File(refPath).writeAsBytes(audioRes.bodyBytes);

      _update('Playing voice sample — keep the phone unblocked.', 0.40);
      await _recorder.start(
        const RecordConfig(
          encoder:            AudioEncoder.wav,
          sampleRate:         16000,
          numChannels:        1,
          echoCancel:         false,
          noiseSuppress:      false,
          autoGain:           false,
          androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceCommunication),
        ),
        path: degradedPath,
      );
      await Future.delayed(const Duration(milliseconds: 300));
      await SpeakerControl.enableSpeaker();
      await _refPlayer.setFilePath(refPath);
      await _refPlayer.play();
      await _refPlayer.playerStateStream.firstWhere((s) => s.processingState == ProcessingState.completed);
      await Future.delayed(const Duration(milliseconds: 500));
      final actualPath = await _recorder.stop();
      await SpeakerControl.disableSpeaker();

      final resolvedPath = actualPath ?? degradedPath;
      _update('Voice captured ✓ Sending for analysis…', 0.65);

      final req = http.MultipartRequest('POST', Uri.parse('$_apiBase/pesq/score'));
      req.files.add(await http.MultipartFile.fromPath('degraded_audio', resolvedPath));
      req.files.add(await http.MultipartFile.fromPath('room_noise', noisePath));
      if (_sessionId != null) req.headers['x-session-id'] = _sessionId!;

      _update('Analysing voice clarity…', 0.75);
      final streamed = await req.send().timeout(const Duration(minutes: 2));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) throw Exception('Server error: $body');

      final data = jsonDecode(body) as Map<String, dynamic>;
      final mos  = (data['mos_score'] as num?)?.toDouble();

      _update('Voice test complete', 1.0);
      _finishWithSuccess({'MOS Score': mos?.toStringAsFixed(2) ?? 'N/A'});
    } catch (e) {
      try { await _recorder.stop(); } catch (_) {}
      try { await SpeakerControl.disableSpeaker(); } catch (_) {}
      _finishWithError(e.toString());
    }
  }

  void _update(String msg, double frac) {
    widget.onProgressUpdate(msg, frac);
    if (mounted) setState(() => _statusMsg = msg);
  }

  void _finishWithSuccess(Map<String, dynamic> scores) {
    if (!mounted) return;
    Navigator.of(context).pop(TestResult(
      id:          TestId.pesq,
      status:      TestStatus.done,
      scores:      scores,
      completedAt: DateTime.now(),
    ));
  }

  void _finishWithError(String msg) {
    if (mounted) setState(() { _isProcessing = false; _errorMsg = msg; });
    widget.onProgressUpdate('Failed: $msg', 1.0);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pop(TestResult(
          id:           TestId.pesq,
          status:       TestStatus.failed,
          errorMessage: msg,
          completedAt:  DateTime.now(),
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.record_voice_over_outlined, color: AppTheme.pesqColor, size: 44),
              const SizedBox(height: 16),
              const Text('Voice Clarity Test', style: TextStyle(color: AppTheme.textPri, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 32),
              Text(_errorMsg ?? _statusMsg, textAlign: TextAlign.center, style: TextStyle(color: _errorMsg != null ? AppTheme.bad : AppTheme.textSec, fontSize: 13)),
              if (_isProcessing) ...[
                const SizedBox(height: 20),
                const CircularProgressIndicator(color: AppTheme.pesqColor),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
