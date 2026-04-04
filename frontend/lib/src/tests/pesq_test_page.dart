// lib/src/tests/pesq_test_page.dart
//
// PESQ test page.
// Full guided flow:
//   1. Download reference speech from /audio/pesq.
//   2. Play reference through speaker while recording via mic.
//   3. Upload recording to POST /webrtc/device-call.
//   4. Display PESQ scores (PSTN / VoLTE / VoIP / Device), then pop.
//
// Back button blocked while recording.

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
  Map<String, dynamic>? _webrtcResult;

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
    setState(() { _isProcessing = true; _errorMsg = null; _webrtcResult = null; });

    try {
      // 0. Permission
      _update('Checking microphone permission…', 0.02);
      if (!await _recorder.hasPermission()) {
        throw Exception('Microphone permission denied. Grant access in Settings.');
      }

      final tmpDir      = await getTemporaryDirectory();
      final recordPath  = '${tmpDir.path}/pesq_recording.wav';

      // 1. Download reference speech
      _update('Downloading reference speech from server…', 0.10);
      final audioRes = await http
          .get(Uri.parse('$_apiBase/audio/pesq'))
          .timeout(const Duration(seconds: 30));
      if (audioRes.statusCode != 200) {
        throw Exception(
            'Reference speech download failed (${audioRes.statusCode})');
      }
      final refPath = '${tmpDir.path}/pesq_ref.wav';
      await File(refPath).writeAsBytes(audioRes.bodyBytes);

      // 2. Record while playing
      _update('Playing speech & recording… hold phone in call position.', 0.25);
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: false,
          noiseSuppress: false,
          autoGain: false,
          audioInterruption: AudioInterruptionMode.none,
          androidConfig:
              AndroidRecordConfig(audioSource: AndroidAudioSource.camcorder),
        ),
        path: recordPath,
      );
      await Future.delayed(const Duration(milliseconds: 300));
      await SpeakerControl.enableSpeaker();
      await _refPlayer.setFilePath(refPath);
      await _refPlayer.setVolume(1.0);
      await _refPlayer.play();
      await _refPlayer.playerStateStream.firstWhere(
          (s) => s.processingState == ProcessingState.completed);
      await Future.delayed(const Duration(milliseconds: 500));
      await _recorder.stop();
      await SpeakerControl.disableSpeaker();

      // 3. Validate
      final recFile = File(recordPath);
      if (!await recFile.exists() || await recFile.length() == 0) {
        throw Exception('Recording failed — no audio captured.');
      }

      // 4. Upload to /webrtc/device-call
      _update('Processing through WebRTC codecs (Opus, G.711, AMR-WB)…', 0.60);
      final req = http.MultipartRequest(
          'POST', Uri.parse('$_apiBase/webrtc/device-call'));
      req.files.add(await http.MultipartFile.fromPath(
        'recorded_audio', recordPath,
        filename: 'webrtc_recording.wav',
      ));
      if (_sessionId != null) req.headers['x-session-id'] = _sessionId!;

      _update('Computing PESQ scores…', 0.80);
      final streamed =
          await req.send().timeout(const Duration(minutes: 2));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) {
        throw Exception('PESQ server error (${streamed.statusCode}): $body');
      }

      final data = jsonDecode(body) as Map<String, dynamic>;
      setState(() => _webrtcResult = data);

      _update('PESQ complete', 1.0);

      final voip   = (data['voip_wideband']?['pesq_score']          as num?)?.toDouble();
      final trad   = (data['traditional_narrowband']?['pesq_score']  as num?)?.toDouble();
      final volte  = (data['volte_wideband']?['pesq_score']          as num?)?.toDouble();
      final direct = (data['direct_recording']?['pesq_score']        as num?)?.toDouble();

      await Future.delayed(const Duration(seconds: 2));

      _finishWithSuccess({
        'PSTN (G.711)':   trad?.toStringAsFixed(2)   ?? 'N/A',
        'VoIP (Opus)':    voip?.toStringAsFixed(2)   ?? 'N/A',
        'VoLTE (AMR-WB)': volte?.toStringAsFixed(2)  ?? 'N/A',
        'Device Score':   direct?.toStringAsFixed(2) ?? 'N/A',
      });
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

  // ── PESQ score helpers ────────────────────────────────────────────────────

  Color _pesqColor(double v) {
    if (v >= 3.5) return AppTheme.good;
    if (v >= 2.5) return AppTheme.warn;
    return AppTheme.bad;
  }

  String _pesqLabel(double v) {
    if (v >= 4.0) return 'EXCELLENT';
    if (v >= 3.5) return 'GOOD';
    if (v >= 2.5) return 'FAIR';
    if (v >= 1.5) return 'POOR';
    return 'VERY POOR';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final voip   = (_webrtcResult?['voip_wideband']?['pesq_score']          as num?)?.toDouble();
    final trad   = (_webrtcResult?['traditional_narrowband']?['pesq_score']  as num?)?.toDouble();
    final volte  = (_webrtcResult?['volte_wideband']?['pesq_score']          as num?)?.toDouble();

    return PopScope(
      canPop: !_isProcessing,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.pesqColor.withOpacity(0.12),
                      border: Border.all(
                          color: AppTheme.pesqColor.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.record_voice_over_outlined,
                        color: AppTheme.pesqColor, size: 28),
                  ),
                  const SizedBox(height: 16),
                  const Text('PESQ Test',
                      style: TextStyle(
                          color: AppTheme.textPri,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('Speech quality via WebRTC',
                      style: TextStyle(
                          color: AppTheme.textSec, fontSize: 13)),
                  const SizedBox(height: 36),

                  // Score grid or pulse ring
                  if (_webrtcResult != null)
                    _PesqScoreGrid(
                      trad: trad, voip: voip, volte: volte,
                      pesqColor: _pesqColor,
                      pesqLabel: _pesqLabel,
                    )
                  else
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, __) => Container(
                        width: 120, height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.surface,
                          border: Border.all(
                            color: AppTheme.pesqColor.withOpacity(
                                0.3 + 0.7 * _pulseCtrl.value),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.pesqColor.withOpacity(
                                  0.08 + 0.12 * _pulseCtrl.value),
                              blurRadius: 32, spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.phone_in_talk_outlined,
                            color: AppTheme.pesqColor, size: 44),
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
                          AppTheme.pesqColor),
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

// ── PESQ 3-column score grid ──────────────────────────────────────────────────

class _PesqScoreGrid extends StatelessWidget {
  final double? trad;
  final double? voip;
  final double? volte;
  final Color  Function(double) pesqColor;
  final String Function(double) pesqLabel;

  const _PesqScoreGrid({
    required this.trad,
    required this.voip,
    required this.volte,
    required this.pesqColor,
    required this.pesqLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: [
        Expanded(child: _PesqCol(
          label: 'PSTN', codec: 'G.711',
          score: trad, color: const Color(0xFFE65100),
          pesqColor: pesqColor, pesqLabel: pesqLabel,
        )),
        const SizedBox(width: 8),
        Expanded(child: _PesqCol(
          label: 'VoLTE', codec: 'AMR-WB',
          score: volte, color: const Color(0xFF6A1B9A),
          pesqColor: pesqColor, pesqLabel: pesqLabel,
        )),
        const SizedBox(width: 8),
        Expanded(child: _PesqCol(
          label: 'VoIP', codec: 'Opus',
          score: voip, color: const Color(0xFF1B5E20),
          pesqColor: pesqColor, pesqLabel: pesqLabel,
        )),
      ]),
      const SizedBox(height: 10),
      const Text(
        'Scale: 1.0 (very poor) → 4.5 (excellent)',
        style: TextStyle(color: AppTheme.textDim, fontSize: 11),
        textAlign: TextAlign.center,
      ),
    ]);
  }
}

class _PesqCol extends StatelessWidget {
  final String  label;
  final String  codec;
  final double? score;
  final Color   color;
  final Color  Function(double) pesqColor;
  final String Function(double) pesqLabel;

  const _PesqCol({
    required this.label,
    required this.codec,
    required this.score,
    required this.color,
    required this.pesqColor,
    required this.pesqLabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = score != null ? pesqColor(score!) : AppTheme.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(children: [
        Text(label, style: TextStyle(
            color: color, fontSize: 13, fontWeight: FontWeight.w700)),
        Text(codec, style: const TextStyle(
            color: AppTheme.textDim, fontSize: 10)),
        const SizedBox(height: 8),
        Text(
          score != null ? score!.toStringAsFixed(2) : 'N/A',
          style: TextStyle(
              color: c, fontSize: 26, fontWeight: FontWeight.bold),
        ),
        if (score != null)
          Text(pesqLabel(score!),
              style: TextStyle(color: c, fontSize: 9),
              textAlign: TextAlign.center),
      ]),
    );
  }
}
