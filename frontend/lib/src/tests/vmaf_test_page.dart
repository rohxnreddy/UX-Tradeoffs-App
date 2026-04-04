// lib/src/tests/vmaf_test_page.dart
//
// Full-screen VMAF test page.
// • Enters landscape immersive mode for recording.
// • Plays the reference video while recording the screen.
// • Uploads the recorded file to POST /vmaf/score.
// • Pops with a TestResult when complete (or on error).
//
// The user cannot navigate back mid-test; the back button is hidden while
// recording is in progress to avoid corrupted recordings.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../core/app_config.dart';
import '../core/theme.dart';
import '../runner/test_model.dart';

class VmafTestPage extends StatefulWidget {
  /// Called whenever progress changes so RunningScreen can reflect it.
  final void Function(String message, double fraction) onProgressUpdate;

  const VmafTestPage({super.key, required this.onProgressUpdate});

  @override
  State<VmafTestPage> createState() => _VmafTestPageState();
}

class _VmafTestPageState extends State<VmafTestPage>
    with TickerProviderStateMixin {
  // ── Video player ──────────────────────────────────────────────────────────
  late VideoPlayerController _player;
  bool _playerReady  = false;
  bool _videoVisible = false;
  bool _isFullscreen = false;

  // ── State ─────────────────────────────────────────────────────────────────
  bool    _isProcessing = false;
  bool    _autoStarted  = false;
  String  _statusMsg    = 'Initialising…';
  String? _errorMsg;
  double? _vmafScore;
  String? _recordedPath;

  late AnimationController _pulseCtrl;
  late AnimationController _scoreCtrl;
  late Animation<double>   _scoreAnim;

  static const _recordingWarmup   = Duration(milliseconds: 2500);
  static const _orientationSettle = Duration(milliseconds: 1200);

  String get _apiBase => AppConfig.apiBaseUrl;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _scoreCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _scoreAnim =
        CurvedAnimation(parent: _scoreCtrl, curve: Curves.easeOutExpo);

    _initPlayer().then((_) {
      // Auto-start once the player is ready.
      if (mounted && !_autoStarted) {
        _autoStarted = true;
        _runTest();
      }
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _scoreCtrl.dispose();
    _player.dispose();
    _restoreOrientation();
    super.dispose();
  }

  // ── Player ────────────────────────────────────────────────────────────────

  Future<void> _initPlayer() async {
    _player =
        VideoPlayerController.asset('assets/video/reference.mp4');
    try {
      await _player.initialize();
      if (mounted) setState(() => _playerReady = true);
    } catch (e) {
      if (mounted) {
        setState(() => _statusMsg = 'Failed to load reference video: $e');
      }
    }
  }

  // ── Orientation helpers ───────────────────────────────────────────────────

  Future<void> _enterFullscreen() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky, overlays: []);
    await Future.delayed(const Duration(milliseconds: 600));
    // Re-apply to ensure the immersive flag survived orientation change.
    await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky, overlays: []);
    setState(() {
      _videoVisible = false;
      _isFullscreen = true;
    });
    await Future.delayed(_orientationSettle);
  }

  Future<void> _exitFullscreen() async {
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) setState(() { _isFullscreen = false; _videoVisible = false; });
    await Future.delayed(const Duration(milliseconds: 500));
  }

  void _restoreOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ── Wait for file to stop growing ─────────────────────────────────────────

  Future<void> _waitFileStable(String path) async {
    _update('Finalizing recording…', 0.70);
    final file = File(path);
    int prev = -1, stable = 0;
    while (stable < 2) {
      await Future.delayed(const Duration(milliseconds: 300));
      final size = await file.length();
      if (size == prev && size > 0) { stable++; } else { stable = 0; prev = size; }
    }
    await Future.delayed(const Duration(milliseconds: 500));
  }

  // ── Main test flow ────────────────────────────────────────────────────────

  Future<void> _runTest() async {
    if (!_playerReady) {
      _finishWithError('Video player not ready.');
      return;
    }
    setState(() {
      _isProcessing = true;
      _vmafScore    = null;
      _errorMsg     = null;
      _recordedPath = null;
    });
    _scoreCtrl.reset();

    try {
      _update('Entering fullscreen…', 0.05);
      await _enterFullscreen();

      _update('Starting screen recorder…', 0.10);
      final started =
          await FlutterScreenRecording.startRecordScreen('vmaf_test');
      if (!started) throw Exception('Screen recording permission denied.');

      _update('Warming up recorder…', 0.15);
      await Future.delayed(_recordingWarmup);

      await _player.seekTo(Duration.zero);
      if (mounted) setState(() { _statusMsg = 'Playing reference video…'; _videoVisible = true; });
      _update('Playing reference video…', 0.20);
      await _player.play();

      final dur = _player.value.duration;
      await Future.delayed(dur + const Duration(milliseconds: 300));
      await _player.pause();
      await Future.delayed(const Duration(milliseconds: 200));

      _update('Stopping recorder…', 0.60);
      final path = await FlutterScreenRecording.stopRecordScreen;
      if (path.isEmpty) throw Exception('Recording returned empty path.');

      _recordedPath = path;
      await _exitFullscreen();
      await _waitFileStable(path);

      final fileSize = await File(path).length();
      if (fileSize < 1024) {
        throw Exception('Recording too small (${fileSize}B). Try again.');
      }

      _update(
          'Uploading ${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB…',
          0.80);
      await _uploadAndScore(path);

    } catch (e, st) {
      debugPrint('VMAF error: $e\n$st');
      await _exitFullscreen();
      _finishWithError(e.toString());
    }
  }

  // ── Upload ────────────────────────────────────────────────────────────────

  Future<void> _uploadAndScore(String path) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$_apiBase/vmaf/score'));
    request.files.add(await http.MultipartFile.fromPath(
      'distorted_video', path,
      filename: 'distorted_video.mp4',
    ));

    final streamed = await request.send().timeout(
      const Duration(minutes: 10),
      onTimeout: () => throw Exception('Upload timed out.'),
    );
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception('API ${streamed.statusCode}: $body');
    }

    final data = jsonDecode(body) as Map<String, dynamic>;
    if (!data.containsKey('vmaf_score')) {
      throw Exception("Response missing 'vmaf_score'.");
    }

    final score = (data['vmaf_score'] as num).toDouble();
    if (mounted) {
      setState(() => _vmafScore = score);
      _scoreCtrl.forward();
    }

    _update('VMAF complete', 1.0);

    // Short pause so the user can see the score before we pop.
    await Future.delayed(const Duration(seconds: 2));

    _finishWithSuccess({'VMAF Score': score.toStringAsFixed(2)});
  }

  // ── Navigation helpers ────────────────────────────────────────────────────

  void _update(String msg, double frac) {
    widget.onProgressUpdate(msg, frac);
    if (mounted) setState(() => _statusMsg = msg);
  }

  void _finishWithSuccess(Map<String, dynamic> scores) {
    if (!mounted) return;
    Navigator.of(context).pop(TestResult(
      id:          TestId.vmaf,
      status:      TestStatus.done,
      scores:      scores,
      completedAt: DateTime.now(),
    ));
  }

  void _finishWithError(String msg) {
    if (mounted) setState(() { _isProcessing = false; _errorMsg = msg; });
    widget.onProgressUpdate('Failed: $msg', 1.0);
    // Give user a moment to read the error, then pop with failure.
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pop(TestResult(
          id:           TestId.vmaf,
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
    // Fullscreen recording overlay — pure black with the video.
    if (_isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          if (_playerReady)
            Center(
              child: AspectRatio(
                aspectRatio: _player.value.aspectRatio,
                child: VideoPlayer(_player),
              ),
            ),
          // Cover with black until we actually want the video visible.
          if (!_videoVisible)
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
        ]),
      );
    }

    return PopScope(
      // Prevent back during active test to avoid corrupt recordings.
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
                  // ── Header ──────────────────────────────────────────────
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.vmafColor.withOpacity(0.12),
                      border: Border.all(
                          color: AppTheme.vmafColor.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.videocam_outlined,
                        color: AppTheme.vmafColor, size: 28),
                  ),
                  const SizedBox(height: 16),
                  const Text('VMAF Test',
                      style: TextStyle(
                          color: AppTheme.textPri,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('Video quality assessment',
                      style: TextStyle(
                          color: AppTheme.textSec, fontSize: 13)),
                  const SizedBox(height: 36),

                  // ── Score or pulse ───────────────────────────────────────
                  if (_vmafScore != null)
                    _ScoreDisplay(
                      score: _vmafScore!,
                      scoreAnim: _scoreAnim,
                      color: AppTheme.vmafColor,
                    )
                  else
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, __) => Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.surface,
                          border: Border.all(
                            color: AppTheme.vmafColor.withOpacity(
                                0.3 + 0.7 * _pulseCtrl.value),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.vmafColor.withOpacity(
                                  0.08 + 0.12 * _pulseCtrl.value),
                              blurRadius: 32,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.fullscreen_rounded,
                            color: AppTheme.vmafColor, size: 44),
                      ),
                    ),

                  const SizedBox(height: 32),

                  // ── Status / error ──────────────────────────────────────
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
                          AppTheme.vmafColor),
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

// ── Score display widget ──────────────────────────────────────────────────────

class _ScoreDisplay extends StatelessWidget {
  final double             score;
  final Animation<double>  scoreAnim;
  final Color              color;

  const _ScoreDisplay({
    required this.score,
    required this.scoreAnim,
    required this.color,
  });

  Color get _scoreColor {
    if (score >= 80) return AppTheme.good;
    if (score >= 55) return AppTheme.warn;
    return AppTheme.bad;
  }

  String get _label {
    if (score >= 90) return 'EXCELLENT';
    if (score >= 80) return 'GOOD';
    if (score >= 60) return 'FAIR';
    if (score >= 40) return 'POOR';
    return 'VERY POOR';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scoreAnim,
      builder: (_, __) => Opacity(
        opacity: scoreAnim.value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - scoreAnim.value)),
          child: Column(children: [
            Text(
              score.toStringAsFixed(2),
              style: TextStyle(
                color: _scoreColor,
                fontSize: 72,
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: -2,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: _scoreColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(4),
                border:
                    Border.all(color: _scoreColor.withOpacity(0.25)),
              ),
              child: Text(
                _label,
                style: TextStyle(
                  color: _scoreColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.5,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
