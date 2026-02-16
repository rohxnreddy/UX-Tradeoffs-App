import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';

class PesqTestScreen extends StatefulWidget {
  const PesqTestScreen({super.key});

  @override
  State<PesqTestScreen> createState() => _PesqTestScreenState();
}

class _PesqTestScreenState extends State<PesqTestScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _refPlayer = AudioPlayer();
  final AudioPlayer _playbackPlayer = AudioPlayer();

  bool isCalling = false;
  String statusMessage = "Ready to make a WebRTC call";
  double progress = 0.0;

  // WebRTC call data
  Map<String, dynamic>? webrtcResult;
  String? _webrtcRefPath;
  String? _webrtcWbPath;
  String? _webrtcNbPath;

  // Playback tracking
  int? _currentlyPlayingIndex;

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
    if (_currentlyPlayingIndex == index) {
      await _playbackPlayer.stop();
      setState(() => _currentlyPlayingIndex = null);
      return;
    }
    await _playbackPlayer.stop();
    setState(() => _currentlyPlayingIndex = index);
    await _playbackPlayer.setFilePath(path);
    await _playbackPlayer.setVolume(1.0);
    await _playbackPlayer.play();
  }

  Future<void> runWebRTCCall() async {
    setState(() {
      isCalling = true;
      webrtcResult = null;
      _webrtcRefPath = null;
      _webrtcWbPath = null;
      _webrtcNbPath = null;
      _currentlyPlayingIndex = null;
      statusMessage = "📞 Requesting microphone permission...";
      progress = 0.0;
    });

    await _playbackPlayer.stop();

    try {
      bool hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        throw Exception("Microphone permission denied.");
      }

      final tempDir = await getTemporaryDirectory();
      final recordingPath = '${tempDir.path}/webrtc_recording.wav';

      // Step 1: Download reference speech
      setState(() {
        statusMessage = "📞 Downloading reference speech...";
        progress = 0.1;
      });

      final audioUrl = '$apiBaseUrl/audio/pesq';
      final audioResponse = await http
          .get(Uri.parse(audioUrl))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception("Download timeout"),
          );

      if (audioResponse.statusCode != 200) {
        throw Exception("Failed to download speech audio");
      }

      final refAudioPath = '${tempDir.path}/webrtc_ref_speech.wav';
      await File(refAudioPath).writeAsBytes(audioResponse.bodyBytes);

      // Step 2: Start recording + play speech through speaker
      setState(() {
        statusMessage =
            "📞 Playing speech & recording...\n🔊 Keep phone in normal call position.";
        progress = 0.25;
      });

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: false,
          noiseSuppress: false,
          autoGain: false,
          audioInterruption: AudioInterruptionMode.none,
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.camcorder,
          ),
        ),
        path: recordingPath,
      );

      await Future.delayed(const Duration(milliseconds: 300));

      await _refPlayer.setFilePath(refAudioPath);
      await _refPlayer.setVolume(1.0);
      await _refPlayer.play();

      await _refPlayer.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );

      await Future.delayed(const Duration(milliseconds: 500));
      await _recorder.stop();

      // Step 3: Upload recording to WebRTC device-call endpoint
      setState(() {
        statusMessage = "📞 Processing through WebRTC codecs (Opus & G.711)...";
        progress = 0.6;
      });

      final file = File(recordingPath);
      if (!await file.exists() || await file.length() == 0) {
        throw Exception("Recording failed — no audio captured");
      }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$apiBaseUrl/webrtc/device-call'),
      );
      request.files.add(
        await http.MultipartFile.fromPath(
          'recorded_audio',
          recordingPath,
          filename: 'webrtc_recording.wav',
        ),
      );

      setState(() {
        statusMessage =
            "📞 Computing PESQ scores...\nComparing device + codec quality.";
        progress = 0.8;
      });

      var streamedResponse = await request.send().timeout(
        const Duration(minutes: 2),
      );

      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        final data = jsonDecode(responseBody);

        // Save base64 audio files for playback
        if (data["reference_audio_b64"] != null) {
          final bytes = base64Decode(data["reference_audio_b64"] as String);
          final path = '${tempDir.path}/webrtc_ref.wav';
          await File(path).writeAsBytes(bytes);
          _webrtcRefPath = path;
        }
        if (data["wb_degraded_audio_b64"] != null) {
          final bytes = base64Decode(data["wb_degraded_audio_b64"] as String);
          final path = '${tempDir.path}/webrtc_wb.wav';
          await File(path).writeAsBytes(bytes);
          _webrtcWbPath = path;
        }
        if (data["nb_degraded_audio_b64"] != null) {
          final bytes = base64Decode(data["nb_degraded_audio_b64"] as String);
          final path = '${tempDir.path}/webrtc_nb.wav';
          await File(path).writeAsBytes(bytes);
          _webrtcNbPath = path;
        }

        setState(() {
          webrtcResult = data;
          statusMessage = "WebRTC call complete!";
          progress = 1.0;
          isCalling = false;
        });
      } else {
        throw Exception(
          "Server error (${streamedResponse.statusCode}): $responseBody",
        );
      }
    } catch (e) {
      setState(() {
        statusMessage =
            "Call error: ${e.toString().replaceAll('Exception: ', '')}";
        isCalling = false;
        progress = 0.0;
      });
    }
  }

  String _getPesqDescription(double score) {
    if (score >= 4.0) return "Excellent quality";
    if (score >= 3.0) return "Good quality";
    if (score >= 2.0) return "Poor quality";
    return "Very poor quality";
  }

  Color _getPesqColor(double score) {
    if (score >= 4.0) return Colors.green.shade700;
    if (score >= 3.0) return Colors.orange.shade700;
    if (score >= 2.0) return Colors.deepOrange;
    return Colors.red.shade700;
  }

  void _showSettingsDialog() {
    final controller = TextEditingController(text: apiBaseUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("API Settings"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "Backend URL",
            hintText: "http://192.168.x.x:8000",
          ),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: const Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.teal),
                      SizedBox(width: 8),
                      Text(
                        "How PESQ Works",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Plays reference speech through your phone's speaker, "
                    "records it with the mic, then uploads the recording "
                    "to the backend where it's processed through actual "
                    "WebRTC codecs (Opus & G.711 μ-law).\n\n"
                    "PESQ scores show how your device + each codec "
                    "affects call quality. Results vary by phone!",
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
                color: isCalling ? Colors.teal.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCalling ? Colors.teal : Colors.grey.shade300,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (isCalling)
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
                  if (isCalling && progress > 0) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.teal,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── WebRTC call results ──────────────────────────
            if (webrtcResult != null) _buildWebRTCCard(),

            // WebRTC Call button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isCalling ? null : runWebRTCCall,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: isCalling ? 0 : 4,
                ),
                child: isCalling
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
                          Text("Calling...", style: TextStyle(fontSize: 18)),
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.wifi_calling_3, size: 24),
                          SizedBox(width: 8),
                          Text(
                            "Make WebRTC Call",
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

            // Settings
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isCalling ? null : _showSettingsDialog,
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
    );
  }

  Widget _buildWebRTCCard() {
    final voip = webrtcResult?["voip_wideband"];
    final trad = webrtcResult?["traditional_narrowband"];
    final direct = webrtcResult?["direct_recording"];

    final voipScore = voip?["pesq_score"] as num?;
    final tradScore = trad?["pesq_score"] as num?;
    final directScore = direct?["pesq_score"] as num?;

    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal, width: 2),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_calling_3, color: Colors.teal),
              SizedBox(width: 8),
              Text(
                "WebRTC Codec Call",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            webrtcResult?["description"] ?? "Real WebRTC codec processing",
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Direct recording score (hardware baseline)
          if (directScore != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.speaker_phone,
                    color: Colors.blue.shade700,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Device Hardware Score",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          "Speaker \u2192 mic only (no codec)",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    directScore.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _getPesqColor(directScore.toDouble()),
                    ),
                  ),
                ],
              ),
            ),

          // Playback buttons
          if (_webrtcRefPath != null ||
              _webrtcWbPath != null ||
              _webrtcNbPath != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.headphones, color: Colors.blueGrey, size: 18),
                      SizedBox(width: 6),
                      Text(
                        "Listen & Compare",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_webrtcRefPath != null)
                    _buildPlaybackTile(
                      index: 30,
                      path: _webrtcRefPath!,
                      title: "Original Speech",
                      subtitle: "Clean reference (16 kHz)",
                      icon: Icons.music_note,
                      color: Colors.blue,
                    ),
                  if (_webrtcNbPath != null) ...[
                    const SizedBox(height: 6),
                    _buildPlaybackTile(
                      index: 31,
                      path: _webrtcNbPath!,
                      title: "PSTN Call (G.711 μ-law)",
                      subtitle: "8 kHz narrowband — actual codec",
                      icon: Icons.phone,
                      color: Colors.orange,
                    ),
                  ],
                  if (_webrtcWbPath != null) ...[
                    const SizedBox(height: 6),
                    _buildPlaybackTile(
                      index: 32,
                      path: _webrtcWbPath!,
                      title: "VoIP Call (Opus)",
                      subtitle: "48 kHz wideband — actual codec",
                      icon: Icons.wifi_calling_3,
                      color: Colors.green,
                    ),
                  ],
                ],
              ),
            ),

          // Codec info chips
          if (voip?["codec"] != null || trad?["codec"] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  if (trad?["codec"] != null)
                    Chip(
                      avatar: const Icon(Icons.phone, size: 16),
                      label: Text(
                        "${trad!['codec']}",
                        style: const TextStyle(fontSize: 11),
                      ),
                      backgroundColor: Colors.orange.shade50,
                    ),
                  if (voip?["codec"] != null)
                    Chip(
                      avatar: const Icon(Icons.wifi_calling_3, size: 16),
                      label: Text(
                        "${voip!['codec']}",
                        style: const TextStyle(fontSize: 11),
                      ),
                      backgroundColor: Colors.green.shade50,
                    ),
                ],
              ),
            ),

          // Score comparison
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "PSTN Call",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        "G.711 μ-law",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tradScore != null
                            ? tradScore.toStringAsFixed(2)
                            : "N/A",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: tradScore != null
                              ? _getPesqColor(tradScore.toDouble())
                              : Colors.grey,
                        ),
                      ),
                      if (tradScore != null)
                        Text(
                          _getPesqDescription(tradScore.toDouble()),
                          style: const TextStyle(fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  "vs",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "VoIP Call",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        "Opus codec",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        voipScore != null
                            ? voipScore.toStringAsFixed(2)
                            : "N/A",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: voipScore != null
                              ? _getPesqColor(voipScore.toDouble())
                              : Colors.grey,
                        ),
                      ),
                      if (voipScore != null)
                        Text(
                          _getPesqDescription(voipScore.toDouble()),
                          style: const TextStyle(fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (voipScore != null && tradScore != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "VoIP (Opus) shows ${((voipScore - tradScore) / tradScore * 100).toStringAsFixed(1)}% "
                "${voipScore > tradScore ? 'better' : 'worse'} quality than PSTN (G.711)",
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
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
          onPressed: isCalling ? null : () => _playAudioFile(path, index),
        ),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      ),
    );
  }
}
