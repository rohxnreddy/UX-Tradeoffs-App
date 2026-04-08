// lib/src/tests/peaq_test_page.dart
//
// PEAQ test page.
// Full guided flow:
//   1. Record 3 s of room noise.
//   2. Download reference audio from /audio/peaq.
//   3. Play reference through speaker while recording degraded audio.
//   4. Upload both WAVs to POST /peaq/score.
//   5. Display ODG scores, then pop with TestResult.
//
// Back button is blocked while recording is active.

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

class PeaqTestPage extends StatefulWidget {
  final void Function(String message, double fraction) onProgressUpdate;

  const PeaqTestPage({super.key, required this.onProgressUpdate});

  @override
  State<PeaqTestPage> createState() => _PeaqTestPageState();
}

class _PeaqTestPageState extends State<PeaqTestPage>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder  = AudioRecorder();
  final AudioPlayer   _refPlayer = AudioPlayer();

  bool    _isProcessing = false;
  bool    _autoStarted  = false;
  String  _statusMsg    = 'Initialising…';
  String? _errorMsg;
  double? _odgScore;
  double? _rawOdg;
  double? _wienerOdg;

  late AnimationController _pulseCtrl;

  String  get _apiBase   => AppConfig.apiBaseUrl;
  String? get _sessionId => SessionStore.instance.sessionId;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

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

  // ── Main flow ─────────────────────────────────────────────────────────────

  Future<void> _runTest() async {
    setState(() { _isProcessing = true; _errorMsg = null; _odgScore = null; });

    try {
      // 0. Permission check
      _update('Checking microphone access…', 0.02);
      if (!await _recorder.hasPermission()) {
        throw Exception(
            'Microphone access is required. Please allow it in Settings.');
      }

      final tmpDir      = await getTemporaryDirectory();
      final noisePath   = '${tmpDir.path}/peaq_noise.wav';
      final degradedPath = '${tmpDir.path}/peaq_degraded.wav';

      // 1. Record room noise (3 s)
      _update('Listening to the room for 3 seconds… stay quiet.', 0.10);
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
          echoCancel: false,
          noiseSuppress: false,
          autoGain: false,
          audioInterruption: AudioInterruptionMode.none,
          androidConfig:
          AndroidRecordConfig(audioSource: AndroidAudioSource.defaultSource),
        ),
        path: noisePath,
      );
      await Future.delayed(const Duration(seconds: 3));
      await _recorder.stop();
      _update('Background captured ✓', 0.25);
      await Future.delayed(const Duration(milliseconds: 800));

      // 2. Download reference audio
      _update('Downloading audio sample…', 0.30);
      final audioRes = await http
          .get(Uri.parse('$_apiBase/audio/peaq?playback=1'))
          .timeout(const Duration(seconds: 30));
      if (audioRes.statusCode != 200) {
        throw Exception(
            'Reference audio download failed (${audioRes.statusCode})');
      }
      final refPath = '${tmpDir.path}/peaq_reference.wav';
      await File(refPath).writeAsBytes(audioRes.bodyBytes);

      // 3. Play reference & record degraded simultaneously
      _update('Playing audio — keep the phone still and speaker unblocked.', 0.40);
      // Enable speaker BEFORE starting the recorder so the audio-mode
      // change (MODE_IN_COMMUNICATION) doesn't interrupt an active
      // recording session.
      await SpeakerControl.enableSpeaker();
      await Future.delayed(const Duration(milliseconds: 300));
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
          echoCancel: false,
          noiseSuppress: false,
          autoGain: false,
          audioInterruption: AudioInterruptionMode.none,
          androidConfig:
          AndroidRecordConfig(audioSource: AndroidAudioSource.defaultSource),
        ),
        path: degradedPath,
      );
      await Future.delayed(const Duration(milliseconds: 650));
      await _refPlayer.setFilePath(refPath);
      await _refPlayer.setVolume(1.0);
      await _refPlayer.play();
      await _refPlayer.playerStateStream.firstWhere(
              (s) => s.processingState == ProcessingState.completed);
      await Future.delayed(const Duration(milliseconds: 500));
      await _recorder.stop();
      await SpeakerControl.disableSpeaker();
      _update('Audio captured ✓  Sending for analysis…', 0.65);

      // 4. Validate files
      final degradedFile = File(degradedPath);
      if (!await degradedFile.exists() ||
          await degradedFile.length() == 0) {
        throw Exception('Degraded audio file is empty or missing.');
      }

      // 5. Upload to /peaq/score
      final req =
      http.MultipartRequest('POST', Uri.parse('$_apiBase/peaq/score'));
      req.files.add(await http.MultipartFile.fromPath(
          'degraded_audio', degradedPath));
      req.files
          .add(await http.MultipartFile.fromPath('room_noise', noisePath));
      if (_sessionId != null) req.headers['x-session-id'] = _sessionId!;

      _update('Analysing audio…', 0.75);
      final streamed =
      await req.send().timeout(const Duration(minutes: 2));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) {
        throw Exception('Server error (${streamed.statusCode}): $body');
      }

      final data = jsonDecode(body) as Map<String, dynamic>;
      final odg  = (data['odg_score'] as num?)?.toDouble();
      final raw  = (data['raw_odg']   as num?)?.toDouble();
      final wien = (data['wiener_odg'] as num?)?.toDouble();
      final ffmpeg = (data['ffmpeg_odg'] as num?)?.toDouble();

      setState(() {
        _odgScore  = odg;
        _rawOdg    = raw;
        _wienerOdg = wien;
      });

      _update('Audio test complete', 1.0);

      final scores = <String, dynamic>{};
      if (raw != null) scores['Raw'] = raw.toStringAsFixed(2);
      if (wien != null) scores['Wiener'] = wien.toStringAsFixed(2);
      if (ffmpeg != null) scores['FFmpeg'] = ffmpeg.toStringAsFixed(2);

      _finishWithSuccess(scores);
    } catch (e) {
      _finishWithError(e.toString());
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _update(String msg, double frac) {
    widget.onProgressUpdate(msg, frac);
    if (mounted) setState(() => _statusMsg = msg);
  }

  void _finishWithSuccess(Map<String, dynamic> scores) {
    if (!mounted) return;
    Navigator.of(context).pop(TestResult(
      id:          TestId.peaq,
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
          id:           TestId.peaq,
          status:       TestStatus.failed,
          errorMessage: msg,
          completedAt:  DateTime.now(),
        ));
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isProcessing,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.peaqColor.withOpacity(0.12),
                      border: Border.all(
                          color: AppTheme.peaqColor.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.music_note_outlined,
                        color: AppTheme.peaqColor, size: 28),
                  ),
                  const SizedBox(height: 16),
                  const Text('Audio Quality Test',
                      style: TextStyle(
                          color: AppTheme.textPri,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('Measuring how clearly your speaker sounds',
                      style: TextStyle(
                          color: AppTheme.textSec, fontSize: 13)),
                  const SizedBox(height: 36),

                  // Pulse ring (always shown while test runs)
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) => Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.surface,
                        border: Border.all(
                          color: AppTheme.peaqColor.withOpacity(
                              0.3 + 0.7 * _pulseCtrl.value),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.peaqColor.withOpacity(
                                0.08 + 0.12 * _pulseCtrl.value),
                            blurRadius: 32, spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.mic_outlined,
                          color: AppTheme.peaqColor, size: 44),
                    ),
                  ),

                  const SizedBox(height: 32),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _errorMsg ?? _statusMsg,
                      key: ValueKey(_errorMsg ?? _statusMsg),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _errorMsg != null
                            ? AppTheme.bad
                            : AppTheme.textSec,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                  ),

                  if (_isProcessing) ...[
                    const SizedBox(height: 20),
                    LinearProgressIndicator(
                      backgroundColor: AppTheme.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppTheme.peaqColor),
                      minHeight: 2,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── ODG score display ─────────────────────────────────────────────────────────

class _OdgDisplay extends StatelessWidget {
  final double  odg;
  final double? raw;
  final double? wiener;

  const _OdgDisplay({required this.odg, this.raw, this.wiener});

  Color _odgColor(double v) {
    if (v >= -1) return AppTheme.good;
    if (v >= -2) return AppTheme.warn;
    return AppTheme.bad;
  }

  String _odgLabel(double v) {
    if (v >= -1) return 'EXCELLENT';
    if (v >= -2) return 'GOOD';
    if (v >= -3) return 'FAIR';
    if (v >= -4) return 'POOR';
    return 'VERY POOR';
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(
        odg.toStringAsFixed(2),
        style: TextStyle(
          color: _odgColor(odg),
          fontSize: 72,
          fontWeight: FontWeight.w800,
          height: 1,
          letterSpacing: -2,
        ),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: _odgColor(odg).withOpacity(0.08),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _odgColor(odg).withOpacity(0.25)),
        ),
        child: Text(
          _odgLabel(odg),
          style: TextStyle(
            color: _odgColor(odg),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.5,
          ),
        ),
      ),
      if (raw != null || wiener != null) ...[
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (raw != null)
              _MiniCard(label: 'Raw', value: raw!, color: AppTheme.warn),
            if (raw != null && wiener != null)
              const SizedBox(width: 10),
            if (wiener != null)
              _MiniCard(
                  label: 'Wiener', value: wiener!, color: AppTheme.good),
          ],
        ),
      ],
      const SizedBox(height: 8),
      const Text(
        'Higher scores = better quality',
        style: TextStyle(color: AppTheme.textDim, fontSize: 11),
        textAlign: TextAlign.center,
      ),
    ]);
  }
}

class _MiniCard extends StatelessWidget {
  final String label;
  final double value;
  final Color  color;
  const _MiniCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(children: [
        Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value.toStringAsFixed(2),
            style: TextStyle(
                color: color, fontSize: 22, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}
