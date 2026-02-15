import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class IQAPage extends StatefulWidget {
  const IQAPage({Key? key}) : super(key: key);

  @override
  State<IQAPage> createState() => _IQAPageState();
}

class _IQAPageState extends State<IQAPage> {
  final ImagePicker _picker = ImagePicker();

  File? _image;
  bool _loading = false;

  double? _brisque;
  double? _niqe;
  double? _piqe;

  Future<void> _captureAndSend() async {
    final XFile? photo =
    await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);

    if (photo == null) return;

    setState(() {
      _image = File(photo.path);
      _loading = true;
      _brisque = null;
      _niqe = null;
      _piqe = null;
    });

    await _sendToAPI(_image!);
  }

  Future<void> _sendToAPI(File imageFile) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("http://192.168.0.102:8000/iqa/score"),
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
        _showError("Upload failed");
      }
    } catch (e) {
      _showError("Error sending image");
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
      appBar: AppBar(title: const Text("Image Quality Assessment")),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
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