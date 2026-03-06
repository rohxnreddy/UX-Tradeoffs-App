import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// ─────────────────────────────────────────────────────────────────
//  Full-screen camera preview / capture
// ─────────────────────────────────────────────────────────────────
class CameraPreviewPage extends StatefulWidget {
  final CameraDescription camera;
  final String label;

  const CameraPreviewPage({
    Key? key,
    required this.camera,
    required this.label,
  }) : super(key: key);

  @override
  State<CameraPreviewPage> createState() => _CameraPreviewPageState();
}

class _CameraPreviewPageState extends State<CameraPreviewPage> {
  late CameraController _ctrl;
  late Future<void> _initFuture;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = CameraController(widget.camera, ResolutionPreset.high, enableAudio: false);
    _initFuture = _ctrl.initialize();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      await _initFuture;
      final XFile raw = await _ctrl.takePicture();
      final dir  = await getTemporaryDirectory();
      final dest = p.join(dir.path,
          'iqa_${widget.label.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(raw.path).copy(dest);
      if (mounted) Navigator.of(context).pop(File(dest));
    } catch (e) {
      setState(() => _capturing = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Capture error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Cannot open camera:\n${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white)),
              ),
            );
          }
          return Stack(fit: StackFit.expand, children: [
            CameraPreview(_ctrl),

            // Back
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 8,
              left: 12,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(ctx).pop(null),
              ),
            ),

            // Label
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 14,
              left: 0, right: 0,
              child: Center(
                child: Text(widget.label,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                  ),
                ),
              ),
            ),

            // Shutter
            Positioned(
              bottom: 44, left: 0, right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _shoot,
                  child: AnimatedOpacity(
                    opacity: _capturing ? 0.4 : 1.0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade300, width: 4),
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.black87, size: 34),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  IQA Page
// ─────────────────────────────────────────────────────────────────
class IQAPage extends StatefulWidget {
  const IQAPage({Key? key}) : super(key: key);

  @override
  State<IQAPage> createState() => _IQAPageState();
}

class _IQAPageState extends State<IQAPage> {
  final TextEditingController _urlCtrl = TextEditingController();

  // Exactly one rear and one front — null if not found on device
  CameraDescription? _rearCam;
  CameraDescription? _frontCam;
  bool _camerasLoading = true;
  String? _cameraError;

  File? _rearImage;
  File? _frontImage;

  bool _loading = false;
  String _apiBaseUrl = 'http://192.168.0.102:8000';
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    _loadApiUrl();
    _detectCameras();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  // ── Pick first back + first front from availableCameras() ─────

  Future<void> _detectCameras() async {
    setState(() { _camerasLoading = true; _cameraError = null; });
    try {
      final all = await availableCameras();
      setState(() {
        _rearCam  = all.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => all.first,
        );
        _frontCam = all.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => all.last,
        );
        _camerasLoading = false;
      });
    } catch (e) {
      setState(() { _cameraError = e.toString(); _camerasLoading = false; });
    }
  }

  // ── Open a specific camera ────────────────────────────────────

  Future<void> _openCamera(CameraDescription cam, String label) async {
    final result = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => CameraPreviewPage(camera: cam, label: label),
      ),
    );
    if (result != null) {
      setState(() {
        if (label == 'Rear Camera') {
          _rearImage = result;
        } else {
          _frontImage = result;
        }
        _results = [];
      });
    }
  }

  // ── Send to API ───────────────────────────────────────────────

  Future<void> _sendToAPI() async {
    // Build ordered list of (label, file) for images that were captured
    final toSend = <MapEntry<String, File>>[];
    if (_rearImage  != null) toSend.add(MapEntry('Rear Camera',  _rearImage!));
    if (_frontImage != null) toSend.add(MapEntry('Front Camera', _frontImage!));

    if (toSend.isEmpty) { _showError('Capture at least one image first.'); return; }

    setState(() { _loading = true; _results = []; });

    try {
      final req = http.MultipartRequest('POST', Uri.parse('$_apiBaseUrl/iqa/score'));
      for (final e in toSend) {
        req.files.add(await http.MultipartFile.fromPath('images', e.value.path));
      }

      final res  = await req.send();
      final body = await res.stream.bytesToString();

      if (res.statusCode == 200) {
        final data = jsonDecode(body);
        final List<dynamic> api = data['results'];
        setState(() {
          _results = List.generate(api.length, (i) => {
            'label':   toSend[i].key,
            'icon':    toSend[i].key == 'Rear Camera'
                ? Icons.camera_rear
                : Icons.camera_front,
            'brisque': (api[i]['brisque'] as num).toDouble(),
            'niqe':    (api[i]['niqe']    as num).toDouble(),
            'piqe':    (api[i]['piqe']    as num).toDouble(),
          });
        });
      } else {
        _showError('Upload failed (${res.statusCode})\n$body');
      }
    } catch (e) {
      _showError('Error: $e');
    }
    setState(() => _loading = false);
  }

  void _showError(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ── API settings ──────────────────────────────────────────────

  Future<void> _loadApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _apiBaseUrl = prefs.getString('api_base_url') ?? 'http://192.168.0.102:8000');
  }

  Future<void> _saveApiUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', url);
    setState(() => _apiBaseUrl = url);
  }

  void _showApiSettings() {
    _urlCtrl.text = _apiBaseUrl;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('API Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('API Base URL:', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _urlCtrl,
              decoration: InputDecoration(
                hintText: 'http://192.168.0.102:8000',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            const Text('Example: http://172.20.10.2:8000',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              String url = _urlCtrl.text.trim();
              if (url.endsWith('/')) url = url.substring(0, url.length - 1);
              if (url.isNotEmpty) {
                _saveApiUrl(url);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('API URL updated')));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── Quality helpers ───────────────────────────────────────────

  String _brisqueLabel(double v) => v < 20 ? 'Excellent' : v < 40 ? 'Good' : v < 60 ? 'Fair' : 'Poor';
  String _niqeLabel(double v)    => v < 3  ? 'Very Good' : v < 5  ? 'Good' : v < 7  ? 'Fair' : 'Poor';
  String _piqeLabel(double v)    => v < 20 ? 'Excellent' : v < 40 ? 'Good' : v < 60 ? 'Fair' : 'Poor';

  Color _qualityColor(String l) {
    if (l == 'Excellent' || l == 'Very Good') return Colors.green;
    if (l == 'Good') return Colors.lightGreen;
    if (l == 'Fair') return Colors.orange;
    return Colors.red;
  }

  // ── Widgets ───────────────────────────────────────────────────

  Widget _cameraHolder({
    required double width,
    required String label,
    required IconData icon,
    required File? image,
    required VoidCallback onTap,
  }) {
    final captured = image != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: captured ? Colors.green.withOpacity(0.08) : Colors.grey.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: captured ? Colors.green : Colors.grey.shade400,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (captured)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(image, height: 90,
                    width: width - 20, fit: BoxFit.cover),
              )
            else
              Icon(icon, size: 48, color: Colors.grey.shade500),
            const SizedBox(height: 8),
            Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500,
                color: captured ? Colors.green : Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              captured ? '✓ Captured • Tap to retake' : 'Tap to open',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: captured ? Colors.green : Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricRow({
    required String title,
    required double value,
    required String Function(double) labelFn,
    required String rangeInfo,
  }) {
    final label = labelFn(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 64,
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
        const SizedBox(width: 6),
        Text(value.toStringAsFixed(2), style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _qualityColor(label).withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _qualityColor(label), width: 1),
          ),
          child: Text(label, style: TextStyle(
              color: _qualityColor(label), fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        const Spacer(),
        Text(rangeInfo, style: const TextStyle(fontSize: 11, color: Colors.black45)),
      ]),
    );
  }

  Widget _resultCard(Map<String, dynamic> r) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(r['icon'] as IconData, size: 20),
            const SizedBox(width: 8),
            Text(r['label'] as String,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const Divider(height: 16),
          _metricRow(title: 'BRISQUE', value: r['brisque'] as double,
              labelFn: _brisqueLabel, rangeInfo: '0–100'),
          _metricRow(title: 'NIQE',    value: r['niqe']    as double,
              labelFn: _niqeLabel,    rangeInfo: '0–10'),
          _metricRow(title: 'PIQE',    value: r['piqe']    as double,
              labelFn: _piqeLabel,    rangeInfo: '0–100'),
          const SizedBox(height: 4),
          const Text('Lower score = Better quality',
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.black45)),
        ]),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasAny = _rearImage != null || _frontImage != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Quality Assessment'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showApiSettings,
            tooltip: 'API Settings',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // API chip
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.link, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(_apiBaseUrl,
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ]),
                  ),
                ),

                const SizedBox(height: 24),

                if (_camerasLoading)
                  const Center(child: CircularProgressIndicator())
                else if (_cameraError != null)
                  Center(child: Column(children: [
                    Text('Detection failed:\n$_cameraError',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _detectCameras,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ]))
                else ...[
                    const Text('Capture Images',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),

                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cardWidth = (constraints.maxWidth - 12) / 2;
                        return Row(
                          children: [
                            if (_rearCam != null)
                              _cameraHolder(
                                width: cardWidth,
                                label: 'Rear Camera',
                                icon: Icons.camera_rear,
                                image: _rearImage,
                                onTap: () => _openCamera(_rearCam!, 'Rear Camera'),
                              ),
                            if (_rearCam != null && _frontCam != null)
                              const SizedBox(width: 12),
                            if (_frontCam != null)
                              _cameraHolder(
                                width: cardWidth,
                                label: 'Front Camera',
                                icon: Icons.camera_front,
                                image: _frontImage,
                                onTap: () => _openCamera(_frontCam!, 'Front Camera'),
                              ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: hasAny && !_loading ? _sendToAPI : null,
                        icon: const Icon(Icons.analytics),
                        label: const Text('Analyse Images'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],

                const SizedBox(height: 20),

                if (_loading) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 12),
                  const Center(child: Text('Analysing images…')),
                ],

                if (_results.isNotEmpty) ...[
                  const Text('Results',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ..._results.map((r) => _resultCard(r)).toList(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}