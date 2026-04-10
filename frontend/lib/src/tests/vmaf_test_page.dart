// lib/src/tests/vmaf_test_page.dart
//
// Flow:
//   1. Page opens → video loads → recording starts automatically.
//   2. OS screen-recording / share-sheet prompt fires with no user tap needed.
//   3. Video plays while screen is recorded.
//   4. Recording stops → page POPS IMMEDIATELY back to RunningScreen.
//   5. Upload runs in the background.  When done, [onResultReady] is called
//      so RunningScreen can patch the placeholder result before Results appear.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../core/app_config.dart';
import '../core/session_store.dart';
import '../core/theme.dart';
import '../runner/test_model.dart';

class VmafTestPage extends StatefulWidget {
  /// Live progress shown on the RunningScreen tile while this page is on top.
  final void Function(String message, double fraction) onProgressUpdate;

  /// Called from the background once the upload finishes (success or failure).
  /// RunningScreen patches its result list with this so Results shows the score.
  final void Function(TestResult result) onResultReady;

  const VmafTestPage({
    super.key,
    required this.onProgressUpdate,
    required this.onResultReady,
  });

  @override
  State<VmafTestPage> createState() => _VmafTestPageState();
}

// idle    → player loading
// recording → recording + playing
// done    → popped
enum _VmafState { idle, recording, done }

class _VmafTestPageState extends State<VmafTestPage>
    with TickerProviderStateMixin {
  late VideoPlayerController _player;
  bool _playerReady = false;
  bool _videoVisible = false;
  bool _isFullscreen = false;

  _VmafState _state = _VmafState.idle;
  String _statusMsg = 'Getting ready…';
  String? _errorMsg;

  late AnimationController _pulseCtrl;

  static const _recordingWarmup = Duration(milliseconds: 2500);
  static const _orientationSettle = Duration(milliseconds: 1200);

  String get _apiBase => AppConfig.apiBaseUrl;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _initPlayer();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _player.dispose();
    _restoreOrientation();
    super.dispose();
  }

  // ── Player ────────────────────────────────────────────────────────────────

  Future<void> _initPlayer() async {
    _player = VideoPlayerController.asset('assets/video/reference.mp4');
    try {
      await _player.initialize();
      if (mounted) {
        setState(() {
          _playerReady = true;
          _statusMsg = 'Starting recording…';
        });
        // Auto-start immediately — no user tap required.
        _startRecording();
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _statusMsg = 'Could not load the video clip. Please try again.',
        );
      }
      widget.onProgressUpdate('Video test failed', 1.0);
      widget.onResultReady(
        TestResult(
          id: TestId.vmaf,
          status: TestStatus.failed,
          errorMessage: 'Video failed to load: $e',
          completedAt: DateTime.now(),
        ),
      );
    }
  }

  // ── Orientation helpers ───────────────────────────────────────────────────

  Future<void> _enterFullscreen() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    await Future.delayed(const Duration(milliseconds: 600));
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    setState(() {
      _videoVisible = false;
      _isFullscreen = true;
    });
    await Future.delayed(_orientationSettle);
  }

  Future<void> _exitFullscreen() async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted)
      setState(() {
        _isFullscreen = false;
        _videoVisible = false;
      });
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

  // ── File-stable wait ──────────────────────────────────────────────────────

  Future<void> _waitFileStable(String path) async {
    final file = File(path);
    int prev = -1, stable = 0;
    while (stable < 2) {
      await Future.delayed(const Duration(milliseconds: 300));
      final size = await file.length();
      if (size == prev && size > 0) {
        stable++;
      } else {
        stable = 0;
        prev = size;
      }
    }
    await Future.delayed(const Duration(milliseconds: 500));
  }

  // ── Automated recording flow ──────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (!_playerReady || _state != _VmafState.idle) return;

    setState(() {
      _state = _VmafState.recording;
      _statusMsg = 'Starting recording…';
      _errorMsg = null;
    });

    try {
      await _enterFullscreen();

      // Triggers the OS share / screen-recording permission sheet.
      final started = await FlutterScreenRecording.startRecordScreen(
        'vmaf_test',
      );

      if (!started) {
        // Permission denied — report failure and pop back automatically.
        await _exitFullscreen();
        widget.onProgressUpdate('Video test failed', 1.0);
        widget.onResultReady(
          TestResult(
            id: TestId.vmaf,
            status: TestStatus.failed,
            errorMessage: 'Screen recording permission was not granted.',
            completedAt: DateTime.now(),
          ),
        );
        _popWithPlaceholder(failed: true);
        return;
      }

      widget.onProgressUpdate('Recording screen…', 0.20);

      // Warmup — give the recorder a moment before video starts.
      await Future.delayed(_recordingWarmup);

      // Play the video.
      await _player.seekTo(Duration.zero);
      if (mounted) setState(() => _videoVisible = true);
      await _player.play();

      final dur = _player.value.duration;
      await Future.delayed(dur + const Duration(milliseconds: 300));
      await _player.pause();
      await Future.delayed(const Duration(milliseconds: 200));

      widget.onProgressUpdate('Finishing up…', 0.60);
      final path = await FlutterScreenRecording.stopRecordScreen;
      if (path.isEmpty) throw Exception('Recording returned empty path.');

      await _exitFullscreen();
      await _waitFileStable(path);

      final fileSize = await File(path).length();
      if (fileSize < 1024) {
        throw Exception('Recording was too short or empty.');
      }

      // ── Pop immediately — upload runs in background ───────────────────────
      widget.onProgressUpdate('Sending in background…', 0.70);
      _popWithPlaceholder();

      // Don't await — this outlives the page.
      _uploadInBackground(path); // ignore: unawaited_futures
    } catch (e, st) {
      debugPrint('VMAF error: $e\n$st');
      await _exitFullscreen();
      widget.onProgressUpdate('Video test failed', 1.0);
      widget.onResultReady(
        TestResult(
          id: TestId.vmaf,
          status: TestStatus.failed,
          errorMessage: e.toString(),
          completedAt: DateTime.now(),
        ),
      );
      _popWithPlaceholder(failed: true);
    }
  }

  // ── Pop with a placeholder that RunningScreen holds until upload finishes ──

  void _popWithPlaceholder({bool failed = false}) {
    if (!mounted) return;
    setState(() => _state = _VmafState.done);
    Navigator.of(context).pop(
      failed
          ? TestResult(
              id: TestId.vmaf,
              status: TestStatus.failed,
              scores: const {'Status': 'Failed'},
            )
          : TestResult(
              id: TestId.vmaf,
              status:
                  TestStatus.running, // RunningScreen treats this as "pending"
              scores: const {'Status': 'Uploading in background…'},
            ),
    );
  }

  // ── Background upload ─────────────────────────────────────────────────────

  double _parseVmafScore(Map<String, dynamic> data) {
    dynamic raw = data['vmaf_score'];
    if (raw == null && data['result'] is Map<String, dynamic>) {
      raw = (data['result'] as Map<String, dynamic>)['vmaf_score'];
    }

    if (raw is num) return raw.toDouble();
    if (raw is String) {
      final parsed = double.tryParse(raw);
      if (parsed != null) return parsed;
    }

    return 0.0;
  }

  Future<void> _uploadInBackground(String path) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_apiBase/vmaf/score'),
      );

      final sessionId = SessionStore.instance.sessionId;
      if (sessionId != null) {
        request.headers['x-session-id'] = sessionId;
      }

      request.files.add(
        await http.MultipartFile.fromPath(
          'distorted_video',
          path,
          filename: 'distorted_video.mp4',
        ),
      );

      final streamed = await request.send().timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw Exception('Upload timed out.'),
      );
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode != 200) {
        throw Exception('Server error (${streamed.statusCode}): $body');
      }

      final data = jsonDecode(body) as Map<String, dynamic>;
      final recordId = data['record_id'];

      if (recordId == null) {
        throw Exception('No record_id returned from VMAF upload.');
      }

      // ── Polling Loop ───────────────────────────────────────────────────────
      bool isDone = false;
      int attempts = 0;
      const maxAttempts = 60; // 3 minutes total (3s * 60)

      while (!isDone && attempts < maxAttempts) {
        attempts++;
        if (attempts > 1) {
          await Future.delayed(const Duration(seconds: 3));
        }

        widget.onProgressUpdate('Processing on server…', 0.80);

        final res = await http.get(
          Uri.parse('$_apiBase/vmaf/status/$recordId'),
          headers: sessionId != null ? {'x-session-id': sessionId} : {},
        );

        if (res.statusCode != 200) {
          throw Exception('Status check failed (${res.statusCode}): ${res.body}');
        }

        final statusData = jsonDecode(res.body) as Map<String, dynamic>;
        final status = statusData['status'];

        if (status == 'completed') {
          isDone = true;
          final score = _parseVmafScore(statusData);
          widget.onProgressUpdate('Video test complete', 1.0);
          widget.onResultReady(
            TestResult(
              id: TestId.vmaf,
              status: TestStatus.done,
              scores: {'Video Quality Score': score.toStringAsFixed(2)},
              completedAt: DateTime.now(),
            ),
          );
        } else if (status == 'failed') {
          throw Exception('VMAF processing failed on the server.');
        }
        // else: still 'processing' or 'pending', loop again.
      }

      if (!isDone) {
        throw Exception('VMAF processing timed out.');
      }
    } catch (e) {
      widget.onProgressUpdate('Video test failed', 1.0);
      widget.onResultReady(
        TestResult(
          id: TestId.vmaf,
          status: TestStatus.failed,
          errorMessage: e.toString(),
          completedAt: DateTime.now(),
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Full-screen recording overlay.
    if (_isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_playerReady)
              Center(
                child: AspectRatio(
                  aspectRatio: _player.value.aspectRatio,
                  child: VideoPlayer(_player),
                ),
              ),
            if (!_videoVisible)
              const Positioned.fill(child: ColoredBox(color: Colors.black)),
          ],
        ),
      );
    }

    return PopScope(
      canPop: _state != _VmafState.recording,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Icon ───────────────────────────────────────────────
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.vmafColor.withOpacity(0.12),
                      border: Border.all(
                        color: AppTheme.vmafColor.withOpacity(0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.videocam_outlined,
                      color: AppTheme.vmafColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Video Test',
                    style: TextStyle(
                      color: AppTheme.textPri,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Checking your screen quality',
                    style: TextStyle(color: AppTheme.textSec, fontSize: 13),
                  ),
                  const SizedBox(height: 36),

                  // ── Pulse / record ring ────────────────────────────────
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) => Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.surface,
                        border: Border.all(
                          color: _state == _VmafState.recording
                              ? AppTheme.bad.withOpacity(
                                  0.4 + 0.6 * _pulseCtrl.value,
                                )
                              : AppTheme.vmafColor.withOpacity(0.25),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (_state == _VmafState.recording
                                        ? AppTheme.bad
                                        : AppTheme.vmafColor)
                                    .withOpacity(
                                      _state == _VmafState.recording
                                          ? 0.10 + 0.15 * _pulseCtrl.value
                                          : 0.05,
                                    ),
                            blurRadius: 32,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(
                        _state == _VmafState.recording
                            ? Icons.fiber_manual_record
                            : Icons.hourglass_top_rounded,
                        color: _state == _VmafState.recording
                            ? AppTheme.bad
                            : AppTheme.vmafColor,
                        size: 40,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Status / error ─────────────────────────────────────
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
