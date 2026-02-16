import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class IQAPage extends StatefulWidget {
  const IQAPage({Key? key}) : super(key: key);

  @override
  State<IQAPage> createState() => _IQAPageState();
}

class _IQAPageState extends State<IQAPage> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _urlController = TextEditingController();

  File? _image;
  bool _loading = false;
  String _apiBaseUrl = "http://192.168.0.102:8000"; // Default URL

  double? _brisque;
  double? _niqe;
  double? _piqe;

  @override
  void initState() {
    super.initState();
    _loadApiUrl();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  // Load saved API URL from SharedPreferences
  Future<void> _loadApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiBaseUrl = prefs.getString('api_base_url') ?? "http://192.168.0.102:8000";
    });
  }

  // Save API URL to SharedPreferences
  Future<void> _saveApiUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', url);
    setState(() {
      _apiBaseUrl = url;
    });
  }

  // Show API Settings Dialog
  void _showApiSettingsDialog() {
    _urlController.text = _apiBaseUrl;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('API Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'API Base URL:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  hintText: 'http://192.168.0.102:8000',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              const Text(
                'Example: http://172.20.10.2:8000',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                String newUrl = _urlController.text.trim();

                // Remove trailing slash if present
                if (newUrl.endsWith('/')) {
                  newUrl = newUrl.substring(0, newUrl.length - 1);
                }

                if (newUrl.isNotEmpty) {
                  _saveApiUrl(newUrl);
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('API URL updated successfully')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _captureAndSend() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (photo == null) return;

      setState(() {
        _image = File(photo.path);
        _loading = true;
        _brisque = null;
        _niqe = null;
        _piqe = null;
      });

      await _sendToAPI(_image!);
    } catch (e) {
      _showError("Camera error: ${e.toString()}");
    }
  }

  Future<void> _sendToAPI(File imageFile) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$_apiBaseUrl/iqa/score"),
      );

      request.files.add(
        await http.MultipartFile.fromPath("image", imageFile.path),
      );

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);

        setState(() {
          _brisque = (data["brisque"] as num).toDouble();
          _niqe = (data["niqe"] as num).toDouble();
          _piqe = (data["piqe"] as num).toDouble();
        });
      } else {
        _showError("Upload failed (Status: ${response.statusCode})");
      }
    } catch (e) {
      _showError("Error: ${e.toString()}");
    }

    setState(() {
      _loading = false;
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- QUALITY LABELS ----------

  String _brisqueLabel(double value) {
    if (value < 20) return "Excellent";
    if (value < 40) return "Good";
    if (value < 60) return "Fair";
    return "Poor";
  }

  String _niqeLabel(double value) {
    if (value < 3) return "Very Good";
    if (value < 5) return "Good";
    if (value < 7) return "Fair";
    return "Poor";
  }

  String _piqeLabel(double value) {
    if (value < 20) return "Excellent";
    if (value < 40) return "Good";
    if (value < 60) return "Fair";
    return "Poor";
  }

  Color _qualityColor(String label) {
    switch (label) {
      case "Excellent":
      case "Very Good":
        return Colors.green;
      case "Good":
        return Colors.lightGreen;
      case "Fair":
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  // ---------- METRIC BOX WIDGET ----------

  Widget _metricBox({
    required String title,
    required double? value,
    required String description,
    required String rangeInfo,
    required bool lowerIsBetter,
  }) {
    if (value == null) return const SizedBox();

    String label;

    if (title == "BRISQUE") {
      label = _brisqueLabel(value);
    } else if (title == "NIQE") {
      label = _niqeLabel(value);
    } else {
      label = _piqeLabel(value);
    }

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style:
              const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 6),

            Text(
              "Score: ${value.toStringAsFixed(2)}",
              style: const TextStyle(fontSize: 16),
            ),

            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _qualityColor(label),
              ),
            ),

            const SizedBox(height: 8),

            Text(description),

            const SizedBox(height: 4),

            Text(
              rangeInfo,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),

            const SizedBox(height: 4),

            Text(
              lowerIsBetter
                  ? "Lower score = Better quality"
                  : "Higher score = Better quality",
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Image Quality Assessment"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showApiSettingsDialog,
            tooltip: 'API Settings',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Display current API URL
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        _apiBaseUrl,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                _image != null
                    ? Image.file(_image!, height: 200)
                    : const Text("No image captured"),

                const SizedBox(height: 20),

                ElevatedButton(
                  onPressed: _captureAndSend,
                  child: const Text("Capture Image"),
                ),

                const SizedBox(height: 20),

                if (_loading) const CircularProgressIndicator(),

                _metricBox(
                  title: "BRISQUE",
                  value: _brisque,
                  description:
                  "BRISQUE measures natural scene statistics distortion without a reference image.",
                  rangeInfo: "Typical range: 0–100",
                  lowerIsBetter: true,
                ),

                _metricBox(
                  title: "NIQE",
                  value: _niqe,
                  description:
                  "NIQE evaluates deviation from statistical regularities of natural images.",
                  rangeInfo: "Typical range: 0–10",
                  lowerIsBetter: true,
                ),

                _metricBox(
                  title: "PIQE",
                  value: _piqe,
                  description:
                  "PIQE estimates perceptual image quality using block distortion analysis.",
                  rangeInfo: "Typical range: 0–100",
                  lowerIsBetter: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}