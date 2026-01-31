import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;


class VmafPlayer extends StatefulWidget {
  const VmafPlayer({super.key});

  @override
  State<VmafPlayer> createState() => _VmafPlayerState();
}

class _VmafPlayerState extends State<VmafPlayer> {
  late VideoPlayerController _player;
  bool isProcessing = false;
  bool isFullscreen = false;
  bool hasRecordingPermission = false;
  String? recordedPath;
  double? vmafScore;
  String statusMessage = "Ready to start test";

  String apiUrl = "http://10.0.2.2:8000/vmaf/score";

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _player = VideoPlayerController.asset(
      "assets/video/reference.mp4",
    );

    try {
      await _player.initialize();
      setState(() {});
    } catch (e) {
      setState(() {
        statusMessage = "Error loading video: $e";
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> enterFullscreen() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() {
      isFullscreen = true;
    });
    await Future.delayed(const Duration(milliseconds: 800));
  }

  Future<void> exitFullscreen() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() {
      isFullscreen = false;
    });
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<void> runFullTest() async {
    setState(() {
      isProcessing = true;
      vmafScore = null;
      recordedPath = null;
      statusMessage = "Preparing test...";
    });

    try {
      // Step 1: Enter fullscreen landscape
      setState(() {
        statusMessage = "Switching to fullscreen...";
      });
      await enterFullscreen();

      // Step 2: Start recording (permission will be requested here if not granted)
      setState(() {
        statusMessage = "Starting recording (requesting permission if needed)...";
      });

      bool started = await FlutterScreenRecording.startRecordScreen("vmaf_test");

      if (!started) {
        setState(() {
          hasRecordingPermission = false;
        });
        throw Exception("Failed to start screen recording. Permission may have been denied.");
      }

      // Permission was granted
      setState(() {
        hasRecordingPermission = true;
      });

      await Future.delayed(const Duration(milliseconds: 800));

      // Step 3: Play video from start
      setState(() {
        statusMessage = "Recording video playback...";
      });

      await _player.seekTo(Duration.zero);
      await _player.play();

      // Wait for video to complete
      final duration = _player.value.duration;
      await Future.delayed(duration + const Duration(milliseconds: 500));

      await _player.pause();
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 4: Stop recording
      setState(() {
        statusMessage = "Stopping recording...";
      });

      String path = await FlutterScreenRecording.stopRecordScreen;

      if (path.isEmpty) {
        throw Exception("Recording failed - no file path returned");
      }

      recordedPath = path;
      print("Recorded video at: $recordedPath");

      // Step 5: Exit fullscreen
      setState(() {
        statusMessage = "Returning to portrait...";
      });
      await exitFullscreen();

      // Verify file exists and has content
      final file = File(recordedPath!);
      if (!await file.exists()) {
        throw Exception("Recorded file does not exist: $recordedPath");
      }

      final fileSize = await file.length();
      if (fileSize == 0) {
        throw Exception("Recorded file is empty");
      }

      print("File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB");

      // Step 6: Upload to API
      setState(() {
        statusMessage = "Uploading to API (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)...";
      });

      await sendToApi();

      setState(() {
        statusMessage = "Test completed successfully!";
        isProcessing = false;
      });

      _showSuccessDialog();

    } catch (e, stackTrace) {
      print("Error: $e");
      print("Stack trace: $stackTrace");

      await exitFullscreen();

      setState(() {
        statusMessage = "Error occurred";
        isProcessing = false;
      });

      if (mounted) {
        _showErrorDialog(e.toString());
      }
    }
  }

  Future<void> sendToApi() async {
    try {
      if (recordedPath == null) {
        throw Exception("No recorded video path available");
      }

      final file = File(recordedPath!);

      if (!await file.exists()) {
        throw Exception("Video file not found at: $recordedPath");
      }

      final fileSize = await file.length();
      if (fileSize == 0) {
        throw Exception("Video file is empty");
      }

      print("Sending file to API: $apiUrl");
      print("File path: $recordedPath");
      print("File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB");

      var request = http.MultipartRequest('POST', Uri.parse(apiUrl));

      // Add the video file
      var multipartFile = await http.MultipartFile.fromPath(
        'distorted_video',
        recordedPath!,
        filename: 'distorted_video.mp4',
      );

      request.files.add(multipartFile);

      print("Sending request...");

      var streamedResponse = await request.send().timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw Exception("Request timed out after 5 minutes");
        },
      );

      print("Response status: ${streamedResponse.statusCode}");

      final responseBody = await streamedResponse.stream.bytesToString();
      print("Response body: $responseBody");

      if (streamedResponse.statusCode == 200) {
        try {
          var data = jsonDecode(responseBody);

          if (data.containsKey("vmaf_score")) {
            setState(() {
              vmafScore = (data["vmaf_score"] as num).toDouble();
            });
            print("VMAF Score: $vmafScore");
          } else {
            throw Exception("API response missing 'vmaf_score' field");
          }
        } catch (e) {
          throw Exception("Failed to parse API response: $e\nResponse: $responseBody");
        }
      } else {
        throw Exception(
            "API Error (${streamedResponse.statusCode}): $responseBody"
        );
      }

    } on SocketException catch (e) {
      throw Exception(
          "Network error: Cannot connect to API server.\n"
              "Make sure:\n"
              "1. API server is running\n"
              "2. Using correct IP (10.0.2.2 for Android emulator)\n"
              "3. Firewall allows connections\n"
              "Details: ${e.message}"
      );
    } on TimeoutException catch (_) {
      throw Exception(
          "Request timed out. The API is taking too long to respond.\n"
              "This may happen with large video files or slow processing."
      );
    } catch (e) {
      rethrow;
    }
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text("Error"),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(error),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green),
            SizedBox(width: 8),
            Text("Success"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("VMAF test completed successfully!"),
            if (vmafScore != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: Column(
                  children: [
                    const Text(
                      "VMAF Score",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      vmafScore!.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Fullscreen mode - only show video
    if (isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: _player.value.isInitialized
              ? AspectRatio(
            aspectRatio: _player.value.aspectRatio,
            child: VideoPlayer(_player),
          )
              : const CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    // Normal portrait mode UI
    return Scaffold(
      appBar: AppBar(
        title: const Text("VMAF Test Player"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: isProcessing ? null : _showSettingsDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Video preview
                if (_player.value.isInitialized)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: _player.value.aspectRatio,
                        child: VideoPlayer(_player),
                      ),
                    ),
                  )
                else
                  Container(
                    height: 200,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),

                const SizedBox(height: 20),

                // Status message
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isProcessing ? Colors.blue.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isProcessing ? Colors.blue : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      if (isProcessing)
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          statusMessage,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // VMAF Score display
                if (vmafScore != null)
                  Container(
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green.shade50, Colors.green.shade100],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle, color: Colors.green),
                            SizedBox(width: 8),
                            Text(
                              "VMAF Score",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          vmafScore!.toStringAsFixed(2),
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _getScoreDescription(vmafScore!),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Start test button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isProcessing || !_player.value.isInitialized
                        ? null
                        : runFullTest,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: isProcessing ? 0 : 4,
                    ),
                    child: isProcessing
                        ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          "Processing...",
                          style: TextStyle(fontSize: 18),
                        ),
                      ],
                    )
                        : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_circle_outline, size: 24),
                        SizedBox(width: 8),
                        Text(
                          "Start VMAF Test",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),

                // View recorded video button
                if (recordedPath != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isProcessing ? null : () => _showRecordedVideo(),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text(
                        "View Recorded Video",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: Colors.blue.shade700, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],

                // File info
                if (recordedPath != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.videocam, size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  recordedPath!.split('/').last,
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          FutureBuilder<int>(
                            future: File(recordedPath!).length(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.storage, size: 16, color: Colors.grey),
                                      const SizedBox(width: 8),
                                      Text(
                                        "Size: ${(snapshot.data! / 1024 / 1024).toStringAsFixed(2)} MB",
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getScoreDescription(double score) {
    if (score >= 95) return "Excellent quality";
    if (score >= 80) return "Good quality";
    if (score >= 60) return "Fair quality";
    if (score >= 40) return "Poor quality";
    return "Very poor quality";
  }

  void _showSettingsDialog() {
    final controller = TextEditingController(text: apiUrl);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("API Settings"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "API Endpoint:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: "http://10.0.2.2:8000/vmaf/score",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Common endpoints:",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "• Android Emulator:\n  http://10.0.2.2:8000/vmaf/score",
                    style: TextStyle(fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "• iOS Simulator:\n  http://127.0.0.1:8000/vmaf/score",
                    style: TextStyle(fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "• Physical Device:\n  http://YOUR_PC_IP:8000/vmaf/score",
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                apiUrl = controller.text.trim();
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("API endpoint updated")),
              );
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showRecordedVideo() {
    if (recordedPath == null) return;

    // Create a new video player for the recorded video
    final recordedVideoController = VideoPlayerController.file(File(recordedPath!));

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: RecordedVideoPlayer(
          videoPath: recordedPath!,
          controller: recordedVideoController,
        ),
      ),
    );
  }
}

class RecordedVideoPlayer extends StatefulWidget {
  final String videoPath;
  final VideoPlayerController controller;

  const RecordedVideoPlayer({
    super.key,
    required this.videoPath,
    required this.controller,
  });

  @override
  State<RecordedVideoPlayer> createState() => _RecordedVideoPlayerState();
}

class _RecordedVideoPlayerState extends State<RecordedVideoPlayer> {
  bool _isInitialized = false;
  bool _isPlaying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      await widget.controller.initialize();
      setState(() {
        _isInitialized = true;
      });
      // Auto-play when opened
      widget.controller.play();
      setState(() {
        _isPlaying = true;
      });

      // Listen for video end
      widget.controller.addListener(() {
        if (widget.controller.value.position >= widget.controller.value.duration) {
          setState(() {
            _isPlaying = false;
          });
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      if (_isPlaying) {
        widget.controller.pause();
        _isPlaying = false;
      } else {
        widget.controller.play();
        _isPlaying = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 600),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade900,
            child: Row(
              children: [
                const Icon(Icons.videocam, color: Colors.white),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "Recorded Video",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Video Player
          Flexible(
            child: Container(
              color: Colors.black,
              child: _error != null
                  ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    "Error loading video:\n$_error",
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
                  : !_isInitialized
                  ? const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              )
                  : Stack(
                alignment: Alignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: widget.controller.value.aspectRatio,
                    child: VideoPlayer(widget.controller),
                  ),
                  // Play/Pause overlay
                  GestureDetector(
                    onTap: _togglePlayPause,
                    child: Container(
                      color: Colors.transparent,
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: _isPlaying ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              size: 64,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Video progress indicator
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: VideoProgressIndicator(
                      widget.controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Colors.blue,
                        bufferedColor: Colors.grey,
                        backgroundColor: Colors.white24,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Controls
          if (_isInitialized)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade900,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    iconSize: 32,
                    onPressed: _togglePlayPause,
                  ),
                  IconButton(
                    icon: const Icon(Icons.replay, color: Colors.white),
                    iconSize: 32,
                    onPressed: () {
                      widget.controller.seekTo(Duration.zero);
                      widget.controller.play();
                      setState(() {
                        _isPlaying = true;
                      });
                    },
                  ),
                  Expanded(
                    child: ValueListenableBuilder(
                      valueListenable: widget.controller,
                      builder: (context, VideoPlayerValue value, child) {
                        final position = value.position;
                        final duration = value.duration;
                        return Text(
                          "${_formatDuration(position)} / ${_formatDuration(duration)}",
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }
}