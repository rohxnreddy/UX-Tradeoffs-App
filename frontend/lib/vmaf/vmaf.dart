import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;

// ── Design tokens ─────────────────────────────────────────────────────────────
class _C {
  static const bg         = Color(0xFFF8F9FA);
  static const surface    = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF1F3F4);
  static const border     = Color(0xFFE0E0E0);
  static const borderLit  = Color(0xFFBDBDBD);
  static const accent     = Color(0xFF0097A7);
  static const accentDim  = Color(0xFF006064);
  static const good       = Color(0xFF2E7D32);
  static const warn       = Color(0xFFF9A825);
  static const bad        = Color(0xFFC62828);
  static const textPri    = Color(0xFF202124);
  static const textSec    = Color(0xFF5F6368);
  static const textDim    = Color(0xFF9AA0A6);
}
// ─────────────────────────────────────────────────────────────────────────────

class VmafPlayer extends StatefulWidget {
  final VoidCallback? onMenuPressed;
  const VmafPlayer({super.key, this.onMenuPressed});

  @override
  State<VmafPlayer> createState() => _VmafPlayerState();
}

class _VmafPlayerState extends State<VmafPlayer> with TickerProviderStateMixin {
  late VideoPlayerController _player;
  bool _playerReady    = false;
  bool _videoVisible   = false; // controls black overlay — false = black screen
  bool isProcessing    = false;
  bool isSendingToApi  = false;
  bool isFullscreen    = false;
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
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    await Future.delayed(const Duration(milliseconds: 600));
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );

    // Ensure video is invisible (black overlay on) before entering fullscreen.
    // This prevents the VideoPlayer texture from showing frame 0 during warmup.
    setState(() {
      _videoVisible = false;
      isFullscreen  = true;
    });

    await Future.delayed(_orientationSettle);
  }

  Future<void> _exitFullscreen() async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() {
      isFullscreen  = false;
      _videoVisible = false;
    });
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<void> _waitUntilFileStable(String path) async {
    final file = File(path);
    int previousSize = -1;
    int stableCount  = 0;

    setState(() => statusMessage = "Finalizing recording...");

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
    final finalSize = await file.length();
    print("Recording finalized: ${(finalSize / 1024 / 1024).toStringAsFixed(2)} MB");
  }

  // ── Main test flow ─────────────────────────────────────────────────────────
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
      // At this point isFullscreen=true, _videoVisible=false
      // Screen is pure black — VideoPlayer texture is hidden by overlay

      setState(() => statusMessage = "Starting recorder...");
      final bool started =
      await FlutterScreenRecording.startRecordScreen("vmaf_test");
      if (!started) throw Exception("Screen recording permission denied.");

      // Warmup: screen stays pure black the entire time
      // _videoVisible remains false → black overlay covers the VideoPlayer
      setState(() => statusMessage = "Warming up recorder...");
      await Future.delayed(_recordingWarmup);

      // Seek to zero while still under black overlay — no frame shown yet
      await _player.seekTo(Duration.zero);

      // NOW reveal the video and start playing simultaneously.
      // This is the scene change Python detects: black → first frame.
      setState(() => statusMessage = "Playing reference video...");
      setState(() => _videoVisible = true);
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
      if (fileSize < 1024) {
        throw Exception("Recording file too small (${fileSize}B) — recording failed.");
      }

      setState(() => statusMessage =
      "Uploading ${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB...");
      await _sendToApi();

      setState(() {
        isProcessing  = false;
        statusMessage = "Done";
      });

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

  // ── API call ───────────────────────────────────────────────────────────────
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
      onTimeout: () => throw Exception("Upload timed out after 10 minutes."),
    );
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception("API returned ${streamed.statusCode}: $body");
    }

    final data = jsonDecode(body);
    if (!data.containsKey("vmaf_score")) {
      throw Exception("Response missing 'vmaf_score' key.");
    }

    setState(() => vmafScore = (data["vmaf_score"] as num).toDouble());
    _scoreCtrl.forward();
  }

  Future<void> _resendToApi() async {
    setState(() {
      isSendingToApi = true;
      errorMessage   = null;
      vmafScore      = null;
      statusMessage  = "Resending to API...";
    });
    _scoreCtrl.reset();

    try {
      await _sendToApi();
      setState(() {
        isSendingToApi = false;
        statusMessage  = "Done";
      });
    } catch (e) {
      setState(() {
        isSendingToApi = false;
        errorMessage   = e.toString();
        statusMessage  = "Failed";
      });
    }
  }

  // ── Score helpers ──────────────────────────────────────────────────────────
  Color  _scoreColor(double s) {
    if (s >= 80) return _C.good;
    if (s >= 55) return _C.warn;
    return _C.bad;
  }
  String _scoreLabel(double s) {
    if (s >= 90) return "EXCELLENT";
    if (s >= 80) return "GOOD";
    if (s >= 60) return "FAIR";
    if (s >= 40) return "POOR";
    return "VERY POOR";
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {

    if (isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // VideoPlayer always in tree so texture stays registered
            if (_playerReady)
              Center(
                child: AspectRatio(
                  aspectRatio: _player.value.aspectRatio,
                  child: VideoPlayer(_player),
                ),
              ),

            // Black overlay covers the VideoPlayer completely during warmup.
            // _videoVisible flips to true only the moment play() is called,
            // creating a guaranteed clean black → first_frame scene change
            // that Python's scene detector picks up on every single run.
            if (!_videoVisible)
              const Positioned.fill(
                child: ColoredBox(color: Colors.black),
              ),
          ],
        ),
      );
    }

    return Theme(
      data: ThemeData.light(),
      child: Scaffold(
        backgroundColor: _C.bg,
        appBar: _buildAppBar(),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildVideoPreview(),
                const SizedBox(height: 16),
                _buildStatusBar(),
                const SizedBox(height: 20),
                if (vmafScore != null) ...[
                  _buildScoreCard(),
                  const SizedBox(height: 20),
                ],
                if (errorMessage != null) ...[
                  _buildErrorCard(),
                  const SizedBox(height: 20),
                ],
                _buildStartButton(),
                if (recordedPath != null) ...[
                  const SizedBox(height: 12),
                  _buildResendButton(),
                  const SizedBox(height: 12),
                  _buildViewRecordingButton(),
                  const SizedBox(height: 12),
                  _buildFileInfo(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _C.surface,
      elevation: 0,
      centerTitle: false,
      leading: widget.onMenuPressed != null
          ? IconButton(
        icon: const Icon(Icons.menu, color: _C.textSec),
        onPressed: widget.onMenuPressed,
      )
          : null,
      title: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: _playerReady ? _C.good : _C.textDim,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          "VMAF  TEST",
          style: TextStyle(
            color: _C.textPri, fontSize: 15,
            fontWeight: FontWeight.w700, letterSpacing: 3,
          ),
        ),
      ]),
      actions: [
        IconButton(
          icon: const Icon(Icons.tune, color: _C.textSec, size: 22),
          onPressed: (isProcessing || isSendingToApi) ? null : _showSettingsDialog,
          tooltip: "API Settings",
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _C.border),
      ),
    );
  }

  Widget _buildVideoPreview() {
    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _C.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              const Text(
                "REFERENCE",
                style: TextStyle(
                  color: _C.textDim, fontSize: 10,
                  fontWeight: FontWeight.w700, letterSpacing: 2,
                ),
              ),
              const Spacer(),
              if (_playerReady) Text(
                "${_player.value.size.width.toInt()}"
                    "×${_player.value.size.height.toInt()}"
                    "  ${_player.value.duration.inSeconds}s",
                style: const TextStyle(
                  color: _C.textDim, fontSize: 10, letterSpacing: 1,
                ),
              ),
            ]),
          ),
          Container(height: 1, color: _C.border),
          AspectRatio(
            aspectRatio: _playerReady ? _player.value.aspectRatio : 16 / 9,
            child: _playerReady
                ? VideoPlayer(_player)
                : Container(
              color: _C.surfaceAlt,
              child: const Center(
                child: CircularProgressIndicator(
                  color: _C.accentDim, strokeWidth: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final busy = isProcessing || isSendingToApi;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _C.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: busy ? _C.accentDim : _C.border),
      ),
      child: Row(children: [
        if (busy)
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Container(
              width: 8, height: 8,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: _C.accent.withOpacity(0.4 + 0.6 * _pulseCtrl.value),
                shape: BoxShape.circle,
              ),
            ),
          )
        else
          Container(
            width: 8, height: 8,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: errorMessage != null
                  ? _C.bad
                  : vmafScore != null ? _C.good : _C.textDim,
              shape: BoxShape.circle,
            ),
          ),
        Expanded(
          child: Text(
            statusMessage,
            style: TextStyle(
              color: busy ? _C.accent : _C.textSec,
              fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.5,
            ),
          ),
        ),
        if (busy)
          const SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: _C.accentDim),
          ),
      ]),
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
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.5), width: 1.5),
              boxShadow: [BoxShadow(
                color: color.withOpacity(0.12), blurRadius: 24,
              )],
            ),
            child: Column(children: [
              Text(
                vmafScore!.toStringAsFixed(2),
                style: TextStyle(
                  color: color, fontSize: 72, fontWeight: FontWeight.w800,
                  height: 1, letterSpacing: -2,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Text(
                  _scoreLabel(vmafScore!),
                  style: TextStyle(
                    color: color, fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildScoreBar(vmafScore!, color),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildScoreBar(double score, Color color) {
    return Column(children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          Text("0",   style: TextStyle(color: _C.textDim, fontSize: 10)),
          Text("50",  style: TextStyle(color: _C.textDim, fontSize: 10)),
          Text("100", style: TextStyle(color: _C.textDim, fontSize: 10)),
        ],
      ),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Stack(children: [
          Container(height: 6, color: _C.surfaceAlt),
          AnimatedBuilder(
            animation: _scoreAnim,
            builder: (_, __) => FractionallySizedBox(
              widthFactor: (score / 100) * _scoreAnim.value,
              child: Container(
                height: 6,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_C.bad, _C.warn, _C.good],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.bad.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _C.bad.withOpacity(0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline, color: _C.bad, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            errorMessage!,
            style: const TextStyle(color: _C.bad, fontSize: 12, height: 1.5),
          ),
        ),
        GestureDetector(
          onTap: () => setState(() => errorMessage = null),
          child: const Icon(Icons.close, color: _C.bad, size: 16),
        ),
      ]),
    );
  }

  Widget _buildStartButton() {
    final busy    = isProcessing || isSendingToApi;
    final enabled = !busy && _playerReady;
    return _PrimaryButton(
      label:   isProcessing ? statusMessage.toUpperCase() : "START VMAF TEST",
      icon:    isProcessing ? null : Icons.play_arrow_rounded,
      busy:    isProcessing,
      enabled: enabled,
      color:   _C.accent,
      onTap:   runFullTest,
    );
  }

  Widget _buildResendButton() {
    final busy    = isProcessing || isSendingToApi;
    final enabled = !busy && recordedPath != null;
    return _PrimaryButton(
      label:   isSendingToApi ? "SENDING..." : "RESEND TO API",
      icon:    isSendingToApi ? null : Icons.refresh_rounded,
      busy:    isSendingToApi,
      enabled: enabled,
      color:   _C.accentDim,
      onTap:   _resendToApi,
    );
  }

  Widget _buildViewRecordingButton() {
    final busy = isProcessing || isSendingToApi;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: busy ? null : _showRecordedVideo,
        style: OutlinedButton.styleFrom(
          foregroundColor: _C.textSec,
          side: const BorderSide(color: _C.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        icon: const Icon(Icons.videocam_outlined, size: 18),
        label: const Text(
          "VIEW RECORDED VIDEO",
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5),
        ),
      ),
    );
  }

  Widget _buildFileInfo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _C.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _C.border),
      ),
      child: Row(children: [
        const Icon(Icons.insert_drive_file_outlined, size: 14, color: _C.textDim),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            recordedPath!.split('/').last,
            style: const TextStyle(
              color: _C.textDim, fontSize: 11, letterSpacing: 0.3,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        FutureBuilder<int>(
          future: File(recordedPath!).length(),
          builder: (_, snap) {
            if (!snap.hasData) return const SizedBox.shrink();
            return Text(
              "${(snap.data! / 1024 / 1024).toStringAsFixed(1)} MB",
              style: const TextStyle(color: _C.textDim, fontSize: 11),
            );
          },
        ),
      ]),
    );
  }

  void _showSettingsDialog() {
    final ctrl = TextEditingController(text: apiUrl);
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: _C.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _C.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "API SETTINGS",
                style: TextStyle(
                  color: _C.textPri, fontSize: 12,
                  fontWeight: FontWeight.w700, letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              const Text("Endpoint",
                  style: TextStyle(color: _C.textSec, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: ctrl,
                style: const TextStyle(color: _C.textPri, fontSize: 13),
                decoration: InputDecoration(
                  hintText: "http://192.168.x.x:8000/vmaf/score",
                  hintStyle: const TextStyle(color: _C.textDim),
                  filled: true,
                  fillColor: _C.surfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: _C.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: _C.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: _C.accentDim),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _C.bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _C.border),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("EMULATOR  →  http://10.0.2.2:8000/vmaf/score",
                        style: TextStyle(color: _C.textDim, fontSize: 11, height: 1.8)),
                    Text("PHYSICAL  →  http://<PC_LAN_IP>:8000/vmaf/score",
                        style: TextStyle(color: _C.textDim, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _C.textSec,
                      side: const BorderSide(color: _C.border),
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
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: const Text("API endpoint saved"),
                        backgroundColor: _C.surfaceAlt,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.accentDim,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text("SAVE",
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w700, letterSpacing: 1)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  void _showRecordedVideo() {
    if (recordedPath == null) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: _RecordedVideoPlayer(
          controller: VideoPlayerController.file(File(recordedPath!)),
        ),
      ),
    );
  }
}

// ── Reusable primary button ───────────────────────────────────────────────────
class _PrimaryButton extends StatelessWidget {
  final String    label;
  final IconData? icon;
  final bool      busy;
  final bool      enabled;
  final Color     color;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.enabled,
    required this.color,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 200),
        child: ElevatedButton(
          onPressed: enabled ? onTap : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: color.withOpacity(0.12),
            foregroundColor: color,
            disabledBackgroundColor: color.withOpacity(0.06),
            disabledForegroundColor: color.withOpacity(0.3),
            elevation: 0,
            side: BorderSide(
              color: enabled ? color.withOpacity(0.5) : color.withOpacity(0.2),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (busy)
              SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
              )
            else if (icon != null)
              Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: color, fontSize: 13,
                fontWeight: FontWeight.w700, letterSpacing: 1.5,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Recorded video player ─────────────────────────────────────────────────────
class _RecordedVideoPlayer extends StatefulWidget {
  final VideoPlayerController controller;
  const _RecordedVideoPlayer({required this.controller});

  @override
  State<_RecordedVideoPlayer> createState() => _RecordedVideoPlayerState();
}

class _RecordedVideoPlayerState extends State<_RecordedVideoPlayer> {
  bool    _ready   = false;
  bool    _playing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await widget.controller.initialize();
      setState(() => _ready = true);
      widget.controller.play();
      setState(() => _playing = true);
      widget.controller.addListener(() {
        if (mounted &&
            widget.controller.value.position >= widget.controller.value.duration) {
          setState(() => _playing = false);
        }
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      if (_playing) {
        widget.controller.pause(); _playing = false;
      } else {
        widget.controller.play(); _playing = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _C.border),
      ),
      constraints: const BoxConstraints(maxHeight: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(bottom: BorderSide(color: _C.border)),
            ),
            child: Row(children: [
              const Text(
                "RECORDED VIDEO",
                style: TextStyle(
                  color: _C.textSec, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, color: _C.textSec, size: 20),
              ),
            ]),
          ),
          Flexible(
            child: _error != null
                ? Padding(
              padding: const EdgeInsets.all(20),
              child: Text(_error!,
                  style: const TextStyle(color: _C.bad, fontSize: 13)),
            )
                : !_ready
                ? const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(
                  color: _C.accentDim, strokeWidth: 2),
            )
                : GestureDetector(
              onTap: _toggle,
              child: Stack(alignment: Alignment.center, children: [
                AspectRatio(
                  aspectRatio: widget.controller.value.aspectRatio,
                  child: VideoPlayer(widget.controller),
                ),
                AnimatedOpacity(
                  opacity: _playing ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _playing ? Icons.pause : Icons.play_arrow,
                      color: Colors.white, size: 48,
                    ),
                  ),
                ),
              ]),
            ),
          ),
          if (_ready)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: _C.surface,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
                border: Border(top: BorderSide(color: _C.border)),
              ),
              child: Column(children: [
                VideoProgressIndicator(
                  widget.controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: _C.accent,
                    bufferedColor: _C.borderLit,
                    backgroundColor: _C.surfaceAlt,
                  ),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                Row(children: [
                  IconButton(
                    icon: Icon(
                      _playing ? Icons.pause : Icons.play_arrow,
                      color: _C.textSec, size: 22,
                    ),
                    onPressed: _toggle,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.replay, color: _C.textDim, size: 20),
                    onPressed: () {
                      widget.controller.seekTo(Duration.zero);
                      widget.controller.play();
                      setState(() => _playing = true);
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const Spacer(),
                  ValueListenableBuilder(
                    valueListenable: widget.controller,
                    builder: (_, VideoPlayerValue v, __) => Text(
                      "${_fmt(v.position)} / ${_fmt(v.duration)}",
                      style: const TextStyle(
                        color: _C.textDim, fontSize: 12, letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$m:$s";
  }
}