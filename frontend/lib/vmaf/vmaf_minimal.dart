import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;

class VmafMinimal extends StatefulWidget {
  final VoidCallback? onMenuPressed;
  const VmafMinimal({super.key, this.onMenuPressed});

  @override
  State<VmafMinimal> createState() => _VmafMinimalState();
}

class _VmafMinimalState extends State<VmafMinimal> with TickerProviderStateMixin {
  late VideoPlayerController _player;
  bool   _playerReady   = false;
  bool   _videoVisible  = false;
  bool   isProcessing   = false;
  bool   isFullscreen   = false;
  String? recordedPath;
  double? vmafScore;
  String  statusMessage = "Ready";
  String? errorMessage;

  String apiUrl = "http://192.168.0.102:8000/vmaf/score";

  late AnimationController _pulseCtrl;
  late AnimationController _scoreCtrl;
  late Animation<double>   _scoreAnim;

  static const Duration _recordingWarmup   = Duration(milliseconds: 2500);
  static const Duration _orientationSettle = Duration(milliseconds: 1200);

  // ── Design tokens (white theme) ────────────────────────────────────────────
  static const _bg      = Color(0xFFFFFFFF);
  static const _surface = Color(0xFFF8F9FA);
  static const _border  = Color(0xFFE0E0E0);
  static const _accent  = Color(0xFF0097A7);
  static const _good    = Color(0xFF2E7D32);
  static const _warn    = Color(0xFFF9A825);
  static const _bad     = Color(0xFFC62828);
  static const _textPri = Color(0xFF202124);
  static const _textSec = Color(0xFF5F6368);
  static const _textDim = Color(0xFF9AA0A6);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scoreCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900),
    );
    _scoreAnim = CurvedAnimation(parent: _scoreCtrl, curve: Curves.easeOutExpo);
    _initializePlayer();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _scoreCtrl.dispose();
    _player.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp, DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    _player = VideoPlayerController.asset("assets/video/reference.mp4");
    try {
      await _player.initialize();
      setState(() => _playerReady = true);
    } catch (e) {
      setState(() => statusMessage = "Failed to load reference video");
    }
  }

  Future<void> _enterFullscreen() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky, overlays: [],
    );
    await Future.delayed(const Duration(milliseconds: 600));
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky, overlays: [],
    );
    setState(() { _videoVisible = false; isFullscreen = true; });
    await Future.delayed(_orientationSettle);
  }

  Future<void> _exitFullscreen() async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() { isFullscreen = false; _videoVisible = false; });
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<void> _waitUntilFileStable(String path) async {
    final file = File(path);
    int previousSize = -1;
    int stableCount  = 0;
    setState(() => statusMessage = "Finalizing...");
    while (stableCount < 2) {
      await Future.delayed(const Duration(milliseconds: 300));
      final currentSize = await file.length();
      if (currentSize == previousSize && currentSize > 0) {
        stableCount++;
      } else {
        stableCount  = 0;
        previousSize = currentSize;
      }
    }
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<void> runFullTest() async {
    setState(() {
      isProcessing  = true;
      vmafScore     = null;
      recordedPath  = null;
      errorMessage  = null;
      statusMessage = "Preparing...";
    });
    _scoreCtrl.reset();

    try {
      setState(() => statusMessage = "Entering fullscreen...");
      await _enterFullscreen();

      setState(() => statusMessage = "Starting recorder...");
      final bool started =
      await FlutterScreenRecording.startRecordScreen("vmaf_test");
      if (!started) throw Exception("Screen recording permission denied.");

      setState(() => statusMessage = "Warming up...");
      await Future.delayed(_recordingWarmup);

      await _player.seekTo(Duration.zero);

      setState(() { statusMessage = "Playing..."; _videoVisible = true; });
      await _player.play();

      final videoDuration = _player.value.duration;
      await Future.delayed(videoDuration + const Duration(milliseconds: 300));
      await _player.pause();
      await Future.delayed(const Duration(milliseconds: 200));

      setState(() => statusMessage = "Stopping recorder...");
      final String path = await FlutterScreenRecording.stopRecordScreen;
      if (path.isEmpty) throw Exception("Recording returned empty path.");

      recordedPath = path;
      await _exitFullscreen();
      await _waitUntilFileStable(path);

      final fileSize = await File(path).length();
      if (fileSize < 1024) throw Exception("Recording file too small (${fileSize}B).");

      setState(() => statusMessage =
      "Uploading ${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB...");
      await _sendToApi();

      setState(() { isProcessing = false; statusMessage = "Done"; });
    } catch (e, st) {
      debugPrint("$e\n$st");
      await _exitFullscreen();
      setState(() {
        isProcessing  = false;
        errorMessage  = e.toString();
        statusMessage = "Failed";
      });
    }
  }

  Future<void> _sendToApi() async {
    if (recordedPath == null) throw Exception("No recording to send.");
    final file     = File(recordedPath!);
    final fileSize = await file.length();
    if (!await file.exists() || fileSize == 0) {
      throw Exception("Recording file missing or empty.");
    }

    final request = http.MultipartRequest('POST', Uri.parse(apiUrl));
    request.files.add(
      await http.MultipartFile.fromPath(
        'distorted_video', recordedPath!,
        filename: 'distorted_video.mp4',
      ),
    );

    final streamed = await request.send().timeout(
      const Duration(minutes: 10),
      onTimeout: () => throw Exception("Upload timed out."),
    );
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw Exception("API ${streamed.statusCode}: $body");
    }

    final data = jsonDecode(body);
    if (!data.containsKey("vmaf_score")) {
      throw Exception("Response missing 'vmaf_score' key.");
    }

    setState(() => vmafScore = (data["vmaf_score"] as num).toDouble());
    _scoreCtrl.forward();
  }

  Color  _scoreColor(double s) {
    if (s >= 80) return _good;
    if (s >= 55) return _warn;
    return _bad;
  }
  String _scoreLabel(double s) {
    if (s >= 90) return "EXCELLENT";
    if (s >= 80) return "GOOD";
    if (s >= 60) return "FAIR";
    if (s >= 40) return "POOR";
    return "VERY POOR";
  }

  @override
  Widget build(BuildContext context) {
    // Fullscreen playback overlay
    if (isFullscreen) {
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
          if (!_videoVisible)
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
        ]),
      );
    }

    final busy    = isProcessing;
    final enabled = !busy && _playerReady;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Centre content ─────────────────────────────────────────────
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Score card
                  if (vmafScore != null) ...[
                    _buildScoreCard(),
                    const SizedBox(height: 40),
                  ],

                  // Error
                  if (errorMessage != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _bad, fontSize: 12, height: 1.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],

                  // Start button
                  _buildStartButton(busy, enabled),

                  const SizedBox(height: 20),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      statusMessage,
                      key: ValueKey(statusMessage),
                      style: const TextStyle(
                        color: _textDim, fontSize: 12,
                        letterSpacing: 1.5, fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Top-left: hamburger ────────────────────────────────────────
            Positioned(
              top: 12,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.menu, color: _textSec, size: 24),
                onPressed: widget.onMenuPressed,
                tooltip: "Menu",
              ),
            ),

            // ── Top-right: IP badge ────────────────────────────────────────
            Positioned(
              top: 16,
              right: 12,
              child: _buildIpBadge(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIpBadge() {
    final host = Uri.tryParse(apiUrl)?.host ?? apiUrl;
    return GestureDetector(
      onTap: isProcessing ? null : _showIpDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6, height: 6,
            decoration: const BoxDecoration(
              color: _accent, shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            host,
            style: const TextStyle(
              color: _textSec, fontSize: 11, letterSpacing: 0.5,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildStartButton(bool busy, bool enabled) {
    return GestureDetector(
      onTap: enabled ? runFullTest : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.35,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _surface,
            border: Border.all(
              color: busy ? _accent.withOpacity(0.5) : _border,
              width: 1.5,
            ),
            boxShadow: busy
                ? [BoxShadow(
              color: _accent.withOpacity(0.12),
              blurRadius: 32, spreadRadius: 4,
            )]
                : [BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16, offset: const Offset(0, 4),
            )],
          ),
          child: Center(
            child: busy
                ? AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => SizedBox(
                width: 36, height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: _accent.withOpacity(0.4 + 0.6 * _pulseCtrl.value),
                ),
              ),
            )
                : Column(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.play_arrow_rounded, color: _textPri, size: 40),
              SizedBox(height: 4),
              Text(
                "START",
                style: TextStyle(
                  color: _textPri, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 3,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildScoreCard() {
    final color = _scoreColor(vmafScore!);
    return AnimatedBuilder(
      animation: _scoreAnim,
      builder: (_, __) => Opacity(
        opacity: _scoreAnim.value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - _scoreAnim.value)),
          child: Column(children: [
            Text(
              vmafScore!.toStringAsFixed(2),
              style: TextStyle(
                color: color, fontSize: 80,
                fontWeight: FontWeight.w800,
                height: 1, letterSpacing: -3,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withOpacity(0.25)),
              ),
              child: Text(
                _scoreLabel(vmafScore!),
                style: TextStyle(
                  color: color, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 2.5,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Stack(children: [
                  Container(height: 4, color: _border),
                  AnimatedBuilder(
                    animation: _scoreAnim,
                    builder: (_, __) => FractionallySizedBox(
                      widthFactor: (vmafScore! / 100) * _scoreAnim.value,
                      child: Container(
                        height: 4,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_bad, _warn, _good],
                            stops: [0.0, 0.5, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showIpDialog() {
    final ctrl = TextEditingController(text: apiUrl);
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "API ENDPOINT",
                style: TextStyle(
                  color: _textPri, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                style: const TextStyle(color: _textPri, fontSize: 13),
                decoration: InputDecoration(
                  hintText: "http://192.168.x.x:8000/vmaf/score",
                  hintStyle: const TextStyle(color: _textDim),
                  filled: true,
                  fillColor: _surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: _border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: _border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: _accent),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Emulator: http://10.0.2.2:8000/vmaf/score\n"
                    "Physical: http://<PC_LAN_IP>:8000/vmaf/score",
                style: TextStyle(color: _textDim, fontSize: 11, height: 1.7),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _textSec,
                      side: const BorderSide(color: _border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text("CANCEL",
                        style: TextStyle(fontSize: 12, letterSpacing: 1)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() => apiUrl = ctrl.text.trim());
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent.withOpacity(0.10),
                      foregroundColor: _accent,
                      elevation: 0,
                      side: BorderSide(color: _accent.withOpacity(0.35)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text("SAVE",
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}