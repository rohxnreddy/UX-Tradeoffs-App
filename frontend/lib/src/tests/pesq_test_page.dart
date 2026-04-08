// lib/src/tests/pesq_test_page.dart
//
// PESQ test page — voice clarity via WebRTC simulator.
// Flow:
//   1. Download reference speech from /audio/pesq.
//   2. Play reference through speaker while recording.
//   3. Upload the device recording to POST /webrtc/device-call.
//   4. Pop with TestResult.

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

      final tmpDir        = await getTemporaryDirectory();
      final recordingPath = '${tmpDir.path}/webrtc_recording.wav';

      _update('Downloading voice sample…', 0.10);
      final audioRes = await http.get(Uri.parse('$_apiBase/audio/pesq?playback=1'));
      if (audioRes.statusCode != 200) throw Exception('Download failed');
      final refPath = '${tmpDir.path}/pesq_reference.wav';
      await File(refPath).writeAsBytes(audioRes.bodyBytes);

      _update('Playing voice sample — keep the phone unblocked.', 0.20);
      // Enable speaker BEFORE starting the recorder so the audio-mode
      // change (MODE_IN_COMMUNICATION) doesn't interrupt an active
      // recording session.
      await SpeakerControl.enableSpeaker();
      await Future.delayed(const Duration(milliseconds: 300));
      await _recorder.start(
        const RecordConfig(
          encoder:            AudioEncoder.wav,
          sampleRate:         16000,
          numChannels:        1,
          echoCancel:         false,
          noiseSuppress:      false,
          autoGain:           false,
          audioInterruption:  AudioInterruptionMode.none,
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.defaultSource,
          ),
        ),
        path: recordingPath,
      );
      await Future.delayed(const Duration(milliseconds: 300));
      await _refPlayer.setFilePath(refPath);
      await _refPlayer.setVolume(1.0);
      await _refPlayer.play();
      await _refPlayer.playerStateStream.firstWhere((s) => s.processingState == ProcessingState.completed);
      await Future.delayed(const Duration(milliseconds: 500));
      final actualPath = await _recorder.stop();
      await SpeakerControl.disableSpeaker();

      final resolvedPath = actualPath ?? recordingPath;
      _update('Voice captured ✓ Processing simulated protocols…', 0.50);

      final req = http.MultipartRequest('POST', Uri.parse('$_apiBase/webrtc/device-call'));
      req.files.add(await http.MultipartFile.fromPath('recorded_audio', resolvedPath));
      if (_sessionId != null) req.headers['x-session-id'] = _sessionId!;

      _update('Analysing voice clarity…', 0.75);
      final streamed = await req.send().timeout(const Duration(minutes: 2));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) throw Exception('Server error: $body');

      final data = jsonDecode(body) as Map<String, dynamic>;
      final branchErrors = <String>[];
      final direct = data['direct_recording'];
      final pstn = data['traditional_narrowband'];
      final volte = data['volte_wideband'];
      final voip = data['voip_wideband'];

      if (direct is Map && direct['error'] != null) {
        branchErrors.add('Device hardware: ${direct['error']}');
      }
      if (pstn is Map && pstn['error'] != null) {
        branchErrors.add('PSTN: ${pstn['error']}');
      }
      if (volte is Map && volte['error'] != null) {
        branchErrors.add('VoLTE: ${volte['error']}');
      }
      if (voip is Map && voip['error'] != null) {
        branchErrors.add('VoIP: ${voip['error']}');
      }
      if (branchErrors.isNotEmpty) {
        throw Exception('Incomplete PESQ analysis: ${branchErrors.join(' | ')}');
      }

      final pstnScore = (pstn?['pesq_score'] as num?)?.toDouble();
      final volteScore = (volte?['pesq_score'] as num?)?.toDouble();
      final voipScore = (voip?['pesq_score'] as num?)?.toDouble();
      final directScore = (direct?['pesq_score'] as num?)?.toDouble();

      final missing = <String>[];
      if (directScore == null) missing.add('Device hardware');
      if (pstnScore == null) missing.add('PSTN');
      if (volteScore == null) missing.add('VoLTE');
      if (voipScore == null) missing.add('VoIP');
      if (missing.isNotEmpty) {
        throw Exception('Incomplete PESQ analysis: missing ${missing.join(', ')}.');
      }

      final scores = <String, dynamic>{};
      if (directScore != null) {
        scores['Device Hardware (WB)'] = directScore.toStringAsFixed(2);
      }
      if (pstnScore != null) {
        scores['PSTN (NB Score)'] = pstnScore.toStringAsFixed(2);
      }
      if (volteScore != null) {
        scores['VoLTE (WB Score)'] = volteScore.toStringAsFixed(2);
      }
      if (voipScore != null) {
        scores['VoIP (WB Score)'] = voipScore.toStringAsFixed(2);
      }
      
      if (scores.isEmpty) scores['Score'] = 'N/A';

      _update('Voice test complete', 1.0);
      _finishWithSuccess(scores);
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
