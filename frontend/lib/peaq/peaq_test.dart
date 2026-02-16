import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';

class PeaqTestScreen extends StatefulWidget {
  const PeaqTestScreen({super.key});

  @override
  State<PeaqTestScreen> createState() => _PeaqTestScreenState();
}

class _PeaqTestScreenState extends State<PeaqTestScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  // Separate players so each can play independently
  final AudioPlayer _refPlayer = AudioPlayer();
  final AudioPlayer _playbackPlayer = AudioPlayer();

  bool isProcessing = false;
  String statusMessage = "Ready to start audio test";
  double progress = 0.0;
  double? odgScore;
  Map<String, dynamic>? resultDetails;

  // Local file paths for recorded/received audio
  String? _roomNoisePath;
  String? _degradedAudioPath;
  String? _subtractedAudioPath;

  // Playback state tracking
  int? _currentlyPlayingIndex; // 0=noise, 1=degraded, 2=subtracted

  String apiBaseUrl = "http://172.20.10.2:8000";

  @override
  void initState() {
    super.initState();
    _playbackPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        setState(() => _currentlyPlayingIndex = null);
      }
    });
  }

  @override
  void dispose() {
    _recorder.dispose();
    _refPlayer.dispose();
    _playbackPlayer.dispose();
    super.dispose();
  }

  Future<void> _playAudioFile(String path, int index) async {
    // If already playing this file, stop it
    if (_currentlyPlayingIndex == index) {
      await _playbackPlayer.stop();
      setState(() => _currentlyPlayingIndex = null);
      return;
    }

    // Stop any current playback
    await _playbackPlayer.stop();

    setState(() => _currentlyPlayingIndex = index);
    await _playbackPlayer.setFilePath(path);
    await _playbackPlayer.setVolume(1.0);
    await _playbackPlayer.play();
  }

  Future<void> runPeaqTest() async {
    setState(() {
      isProcessing = true;
      odgScore = null;
      resultDetails = null;
      _roomNoisePath = null;
      _degradedAudioPath = null;
      _subtractedAudioPath = null;
      _currentlyPlayingIndex = null;
      statusMessage = "Requesting microphone permission...";
      progress = 0.0;
    });

    // Stop any playback
    await _playbackPlayer.stop();

    try {
      // Step 0: Check microphone permission
      bool hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        throw Exception(
          "Microphone permission denied. Please grant microphone access in Settings.",
        );
      }

      // Step 1: Record room noise (ambient)
      setState(() {
        statusMessage =
            "Recording room noise (3 seconds)...\nKeep the room as it normally is.";
        progress = 0.1;
      });

      final tempDir = await getTemporaryDirectory();
      final noisePath = '${tempDir.path}/room_noise.wav';
      final degradedPath = '${tempDir.path}/degraded_audio.wav';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
          echoCancel: false,
          noiseSuppress: false,
          autoGain: false,
          audioInterruption: AudioInterruptionMode.none,
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.camcorder,
          ),
        ),
        path: noisePath,
      );
      await Future.delayed(const Duration(seconds: 3));
      await _recorder.stop();

      setState(() {
        _roomNoisePath = noisePath;
        statusMessage =
            "Room noise captured ✓\nPreparing to play reference audio...";
        progress = 0.25;
      });
      await Future.delayed(const Duration(seconds: 1));

      // Step 2: Download reference audio from backend
      setState(() {
        statusMessage = "Downloading reference audio from server...";
        progress = 0.3;
      });

      final audioUrl = '$apiBaseUrl/audio/peaq';
      final audioResponse = await http
          .get(Uri.parse(audioUrl))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception(
              "Failed to download reference audio — server timeout",
            ),
          );

      if (audioResponse.statusCode != 200) {
        throw Exception(
          "Failed to download reference audio (${audioResponse.statusCode})",
        );
      }

      final refAudioPath = '${tempDir.path}/peaq_reference.wav';
      await File(refAudioPath).writeAsBytes(audioResponse.bodyBytes);

      // Step 3: Start recording degraded audio + play reference through speaker
      setState(() {
        statusMessage =
            "Playing audio & recording...\n🔊 Keep your phone in its normal position.";
        progress = 0.4;
      });

      // Start recording FIRST
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
          echoCancel: false,
          noiseSuppress: false,
          autoGain: false,
          audioInterruption: AudioInterruptionMode.none,
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.camcorder,
          ),
        ),
        path: degradedPath,
      );

      // Small delay to ensure recording has started
      await Future.delayed(const Duration(milliseconds: 300));

      // Play reference audio through speaker
      await _refPlayer.setFilePath(refAudioPath);
      await _refPlayer.setVolume(1.0);
      await _refPlayer.play();

      // Wait for audio to finish
      await _refPlayer.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );

      // Small delay after playback ends
      await Future.delayed(const Duration(milliseconds: 500));

      // Stop recording
      final recordedFile = await _recorder.stop();
      if (recordedFile == null) {
        throw Exception("Recording failed — no audio captured");
      }

      setState(() {
        _degradedAudioPath = degradedPath;
        statusMessage = "Audio captured ✓\nUploading to server for analysis...";
        progress = 0.65;
      });

      // Step 4: Upload BOTH files to backend
      final noiseFile = File(noisePath);
      final degradedFile = File(degradedPath);
      if (!await degradedFile.exists() || await degradedFile.length() == 0) {
        throw Exception("Degraded audio file is empty or missing");
      }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$apiBaseUrl/peaq/score'),
      );
      request.files.add(
        await http.MultipartFile.fromPath(
          'degraded_audio',
          degradedPath,
          filename: 'degraded_audio.wav',
        ),
      );
      // Also upload room noise for spectral subtraction
      if (await noiseFile.exists() && await noiseFile.length() > 0) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'room_noise',
            noisePath,
            filename: 'room_noise.wav',
          ),
        );
      }

      setState(() {
        statusMessage =
            "Analyzing audio quality...\nPerforming spectral subtraction & scoring.";
        progress = 0.8;
      });

      var streamedResponse = await request.send().timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw Exception("Analysis timed out"),
      );

      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        var data = jsonDecode(responseBody);

        // Save subtracted audio if present
        String? subtractedPath;
        if (data["subtracted_audio_b64"] != null) {
          final subtractedBytes = base64Decode(
            data["subtracted_audio_b64"] as String,
          );
          subtractedPath = '${tempDir.path}/subtracted_audio.wav';
          await File(subtractedPath).writeAsBytes(subtractedBytes);
        }

        setState(() {
          odgScore = (data["odg_score"] as num).toDouble();
          resultDetails = data["details"] != null
              ? Map<String, dynamic>.from(data["details"])
              : null;
          _subtractedAudioPath = subtractedPath;
          statusMessage = "Test completed!";
          progress = 1.0;
          isProcessing = false;
        });
      } else {
        throw Exception(
          "Server error (${streamedResponse.statusCode}): $responseBody",
        );
      }
    } catch (e) {
      setState(() {
        statusMessage = "Error: ${e.toString().replaceAll('Exception: ', '')}";
        isProcessing = false;
        progress = 0.0;
      });
    }
  }

  String _getOdgDescription(double score) {
    if (score >= -0.5) return "Imperceptible degradation";
    if (score >= -1.0) return "Perceptible but not annoying";
    if (score >= -2.0) return "Slightly annoying";
    if (score >= -3.0) return "Annoying";
    return "Very annoying degradation";
  }

  Color _getOdgColor(double score) {
    if (score >= -0.5) return Colors.green;
    if (score >= -1.0) return Colors.lightGreen;
    if (score >= -2.0) return Colors.orange;
    if (score >= -3.0) return Colors.deepOrange;
    return Colors.red;
  }

  void _showSettingsDialog() {
    final controller = TextEditingController(text: apiBaseUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("API Settings"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "API Base URL:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: "http://172.20.10.2:8000",
                border: OutlineInputBorder(),
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
                apiBaseUrl = controller.text.trim();
              });
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Info card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          "How PEAQ Works",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      "1. Records ambient room noise (3s)\n"
                      "2. Plays reference audio through speaker\n"
                      "3. Records the degraded audio via mic\n"
                      "4. Subtracts noise & analyzes quality (ODG score)",
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Status
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isProcessing
                      ? Colors.blue.shade50
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isProcessing ? Colors.blue : Colors.grey.shade300,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
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
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isProcessing && progress > 0) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.blue,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Audio Playback Section ──────────────────────
              if (_roomNoisePath != null ||
                  _degradedAudioPath != null ||
                  _subtractedAudioPath != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.headphones,
                            color: Colors.blueGrey,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            "Audio Recordings",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_roomNoisePath != null)
                        _buildPlaybackTile(
                          index: 0,
                          path: _roomNoisePath!,
                          title: "Room Noise",
                          subtitle: "Ambient noise only (3s)",
                          icon: Icons.noise_aware,
                          color: Colors.grey,
                        ),
                      if (_degradedAudioPath != null) ...[
                        const SizedBox(height: 8),
                        _buildPlaybackTile(
                          index: 1,
                          path: _degradedAudioPath!,
                          title: "Degraded Audio",
                          subtitle: "Room noise + audio from speaker",
                          icon: Icons.speaker,
                          color: Colors.orange,
                        ),
                      ],
                      if (_subtractedAudioPath != null) ...[
                        const SizedBox(height: 8),
                        _buildPlaybackTile(
                          index: 2,
                          path: _subtractedAudioPath!,
                          title: "Subtracted Audio",
                          subtitle: "After spectral noise subtraction",
                          icon: Icons.auto_fix_high,
                          color: Colors.green,
                        ),
                      ],
                    ],
                  ),
                ),

              // Score display
              if (odgScore != null)
                Container(
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _getOdgColor(odgScore!).withValues(alpha: 0.1),
                        _getOdgColor(odgScore!).withValues(alpha: 0.2),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getOdgColor(odgScore!),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _getOdgColor(odgScore!).withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.music_note,
                            color: _getOdgColor(odgScore!),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "PEAQ ODG Score",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        odgScore!.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: _getOdgColor(odgScore!),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _getOdgDescription(odgScore!),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Scale: -4.0 (very annoying) to 0.0 (imperceptible)",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),

              // Test button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isProcessing ? null : runPeaqTest,
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
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text("Testing...", style: TextStyle(fontSize: 18)),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.mic, size: 24),
                            SizedBox(width: 8),
                            Text(
                              "Test Audio",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 12),

              // Settings button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isProcessing ? null : _showSettingsDialog,
                  icon: const Icon(Icons.settings),
                  label: const Text("API Settings"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaybackTile({
    required int index,
    required String path,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final isPlaying = _currentlyPlayingIndex == index;

    return Container(
      decoration: BoxDecoration(
        color: isPlaying ? color.withValues(alpha: 0.1) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPlaying ? color : Colors.grey.shade300,
          width: isPlaying ? 2 : 1,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: IconButton(
          icon: Icon(
            isPlaying ? Icons.stop_circle : Icons.play_circle_fill,
            color: color,
            size: 36,
          ),
          onPressed: isProcessing ? null : () => _playAudioFile(path, index),
        ),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      ),
    );
  }
}
