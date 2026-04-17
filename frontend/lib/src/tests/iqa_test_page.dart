// lib/src/tests/iqa_test_page.dart
//
// IQA test page.
// Full guided flow:
//   1. Detect rear and front cameras.
//   2. User captures a photo from each camera via a full-screen preview.
//   3. Both images are uploaded to POST /camara/score.
//   4. Displays BRISQUE / NIQE / PIQE results per camera.
//   5. Pops with a TestResult.
//
// Unlike the runner-only version (which tried to call /iqa/latest without
// any images), this page actually performs the camera capture.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../utils/image_utils.dart';

import '../core/app_config.dart';
import '../core/session_store.dart';
import '../core/theme.dart';
import '../runner/test_model.dart';

// ── Full-screen camera preview / shutter ──────────────────────────────────────

class _CameraPreviewPage extends StatefulWidget {
  final CameraDescription camera;
  final String            label;

  const _CameraPreviewPage({required this.camera, required this.label});

  @override
  State<_CameraPreviewPage> createState() => _CameraPreviewPageState();
}

class _CameraPreviewPageState extends State<_CameraPreviewPage> {
  late CameraController _ctrl;
  late Future<void>     _initFuture;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = CameraController(widget.camera, ResolutionPreset.max,
        enableAudio: false);
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
          'iqa_${widget.label.replaceAll(' ', '_')}_'
              '${DateTime.now().millisecondsSinceEpoch}.jpg');
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
            return const Center(
                child: CircularProgressIndicator(color: Colors.white));
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

            // Back button
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 8,
              left: 12,
              child: IconButton(
                icon: const Icon(Icons.arrow_back,
                    color: Colors.white, size: 28),
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
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(blurRadius: 4, color: Colors.black54)
                      ],
                    )),
              ),
            ),

            // Shutter button
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
                        border: Border.all(
                            color: Colors.grey.shade300, width: 4),
                      ),
                      child: const Icon(Icons.camera_alt,
                          color: Colors.black87, size: 34),
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

// ── IQA Test Page ─────────────────────────────────────────────────────────────

class IqaTestPage extends StatefulWidget {
  final void Function(String message, double fraction) onProgressUpdate;

  const IqaTestPage({super.key, required this.onProgressUpdate});

  @override
  State<IqaTestPage> createState() => _IqaTestPageState();
}

class _IqaTestPageState extends State<IqaTestPage>
    with SingleTickerProviderStateMixin {
  // Cameras
  CameraDescription? _rearCam;
  CameraDescription? _frontCam;
  bool   _camsLoading = true;
  String? _camError;

  // Captured images
  File? _rearImage;
  File? _frontImage;

  // State
  bool    _isAnalysing = false;
  bool    _readyToAnalyse = false;
  String? _errorMsg;
  List<Map<String, dynamic>> _results = [];

  late AnimationController _pulseCtrl;

  String  get _apiBase   => AppConfig.iqaApiBaseUrl;
  String? get _sessionId => SessionStore.instance.sessionId;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _detectCameras();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Camera detection ──────────────────────────────────────────────────────

  Future<void> _detectCameras() async {
    setState(() { _camsLoading = true; _camError = null; });
    try {
      final all = await availableCameras();
      setState(() {
        _rearCam  = all.firstWhere(
                (c) => c.lensDirection == CameraLensDirection.back,
            orElse: () => all.first);
        _frontCam = all.firstWhere(
                (c) => c.lensDirection == CameraLensDirection.front,
            orElse: () => all.last);
        _camsLoading = false;
      });
      widget.onProgressUpdate('Ready — tap a camera to take a photo.', 0.10);
    } catch (e) {
      setState(() { _camError = e.toString(); _camsLoading = false; });
    }
  }

  // ── Camera capture ────────────────────────────────────────────────────────

  Future<void> _openCamera(CameraDescription cam, String label) async {
    final result = await Navigator.of(context).push<File>(
      MaterialPageRoute(builder: (_) =>
          _CameraPreviewPage(camera: cam, label: label)),
    );
    if (result != null) {
      setState(() {
        if (label == 'Rear Camera') {
          _rearImage = result;
        } else {
          _frontImage = result;
        }
        _results = [];
        _readyToAnalyse = _rearImage != null || _frontImage != null;
      });
      final captured = (_rearImage != null ? 1 : 0) +
          (_frontImage != null ? 1 : 0);
      widget.onProgressUpdate(
          '${captured == 1 ? "Photo captured" : "Photos captured"} — tap Check when ready.',
          0.20);
    }
  }

  // ── Upload & analyse ──────────────────────────────────────────────────────

  Future<void> _analyseImages() async {
    setState(() { _isAnalysing = true; _errorMsg = null; _results = []; });
    widget.onProgressUpdate('Sending photos for analysis…', 0.50);

    try {
      final entries = <MapEntry<String, File>>[];
      if (_rearImage  != null) entries.add(MapEntry('Rear Camera',  _rearImage!));
      if (_frontImage != null) entries.add(MapEntry('Front Camera', _frontImage!));

      final req = http.MultipartRequest(
          'POST', Uri.parse('$_apiBase/camara/score'));
      if (_sessionId != null) req.headers['x-session-id'] = _sessionId!;

      for (final e in entries) {
        final resized = await ImageUtils.resizeImageForIQA(e.value);
        req.files.add(await http.MultipartFile.fromPath(
          'images',
          resized.path,
          filename: '${e.key.replaceAll(' ', '_').toLowerCase()}.jpg',
        ));
        req.fields['labels'] = e.key;
      }

      widget.onProgressUpdate('Analysing your photos…', 0.75);
      final streamed =
      await req.send().timeout(const Duration(minutes: 2));
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode != 200) {
        throw Exception('Server error (${streamed.statusCode}): $body');
      }

      final data    = jsonDecode(body) as Map<String, dynamic>;
      final results = (data['results'] as List?)
          ?.cast<Map<String, dynamic>>() ??
          [];

      // Attach label + icon for display
      final icons = {
        'Rear Camera':  Icons.camera_rear,
        'Front Camera': Icons.camera_front,
      };
      for (int i = 0; i < results.length; i++) {
        final label = entries.length > i ? entries[i].key : 'Camera';
        results[i]['label'] = label;
        results[i]['icon']  = icons[label] ?? Icons.image_outlined;
      }

      setState(() { _results = results; _isAnalysing = false; });
      widget.onProgressUpdate('Camera test complete', 1.0);

      _finishWithSuccess(results);
    } catch (e) {
      _finishWithError(e.toString());
    }
  }

  // ── CDI composite score ───────────────────────────────────────────────────

  double _computeCDI({required double brisque, required double niqe, required double piqe}) {
    final bScore = math.max(0.0, (1 - brisque / 100)) * 100;
    final nScore = math.max(0.0, (1 - niqe   /  15)) * 100;
    final pScore = math.max(0.0, (1 - piqe   / 100)) * 100;
    return (math.pow(bScore, 0.20) *
        math.pow(nScore, 0.45) *
        math.pow(pScore, 0.35))
        .toDouble();
  }

  // ── Navigation helpers ────────────────────────────────────────────────────

  void _finishWithSuccess(List<Map<String, dynamic>> results) {
    if (!mounted) return;
    final scores = <String, dynamic>{};
    for (int i = 0; i < results.length; i++) {
      final r     = results[i];
      final label = r['label'] as String? ?? 'Cam ${i + 1}';
      final b     = (r['brisque'] as num?)?.toDouble() ?? 0;
      final n     = (r['niqe']    as num?)?.toDouble() ?? 0;
      final piqe  = (r['piqe']    as num?)?.toDouble() ?? 0;
      scores['$label Score'] =
          _computeCDI(brisque: b, niqe: n, piqe: piqe).toStringAsFixed(1);
    }
    Navigator.of(context).pop(TestResult(
      id:          TestId.iqa,
      status:      TestStatus.done,
      scores:      scores,
      completedAt: DateTime.now(),
    ));
  }

  void _finishWithError(String msg) {
    if (mounted) setState(() { _isAnalysing = false; _errorMsg = msg; });
    widget.onProgressUpdate('Failed: $msg', 1.0);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pop(TestResult(
          id:           TestId.iqa,
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
    return PopScope(
      canPop: !_isAnalysing,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────
                Row(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.iqaColor.withOpacity(0.12),
                      border: Border.all(
                          color: AppTheme.iqaColor.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.image_outlined,
                        color: AppTheme.iqaColor, size: 26),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Camera Quality Test',
                          style: TextStyle(
                              color: AppTheme.textPri,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                      Text('Checking how sharp your camera photos are',
                          style: TextStyle(
                              color: AppTheme.textSec, fontSize: 12)),
                    ],
                  ),
                ]),

                const SizedBox(height: 28),

                const SizedBox(height: 28),

                // ── Camera loading / error ───────────────────────────────
                if (_camsLoading)
                  const Center(child: CircularProgressIndicator(
                      color: AppTheme.iqaColor))
                else if (_camError != null)
                  _ErrorBox(
                    message: 'Camera detection failed:\n$_camError',
                    onRetry: _detectCameras,
                  )
                else ...[
                    // ── Capture cards ──────────────────────────────────────
                    const Text('Capture Images',
                        style: TextStyle(
                            color: AppTheme.textPri,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),

                    Row(children: [
                      if (_rearCam != null)
                        Expanded(
                          child: _CameraCard(
                            label: 'Rear Camera',
                            icon: Icons.camera_rear,
                            image: _rearImage,
                            color: AppTheme.iqaColor,
                            onTap: () => _openCamera(_rearCam!, 'Rear Camera'),
                          ),
                        ),
                      if (_rearCam != null && _frontCam != null)
                        const SizedBox(width: 12),
                      if (_frontCam != null)
                        Expanded(
                          child: _CameraCard(
                            label: 'Front Camera',
                            icon: Icons.camera_front,
                            image: _frontImage,
                            color: AppTheme.iqaColor,
                            onTap: () =>
                                _openCamera(_frontCam!, 'Front Camera'),
                          ),
                        ),
                    ]),

                    const SizedBox(height: 24),

                    // ── Analyse button ─────────────────────────────────────
                    GestureDetector(
                      onTap: (_readyToAnalyse && !_isAnalysing)
                          ? _analyseImages
                          : null,
                      child: AnimatedOpacity(
                        opacity:
                        (_readyToAnalyse && !_isAnalysing) ? 1.0 : 0.35,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          width: double.infinity,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppTheme.iqaColor,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.iqaColor.withOpacity(0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isAnalysing)
                                const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black),
                                )
                              else
                                const Icon(Icons.analytics_outlined,
                                    color: Colors.black, size: 20),
                              const SizedBox(width: 10),
                              Text(
                                _isAnalysing
                                    ? 'Checking…'
                                    : 'Continue',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                // ── Error ──────────────────────────────────────────────
                if (_errorMsg != null) ...[
                  const SizedBox(height: 16),
                  _ErrorBox(message: _errorMsg!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Camera capture card ───────────────────────────────────────────────────────

class _CameraCard extends StatelessWidget {
  final String   label;
  final IconData icon;
  final File?    image;
  final Color    color;
  final VoidCallback onTap;

  const _CameraCard({
    required this.label,
    required this.icon,
    required this.image,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: image != null
              ? Colors.transparent
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: image != null
                  ? color.withOpacity(0.5)
                  : AppTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: image != null
            ? Stack(fit: StackFit.expand, children: [
          Image.file(image!, fit: BoxFit.cover),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(
                  vertical: 6, horizontal: 8),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ])
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Tap to capture',
                style: const TextStyle(
                    color: AppTheme.textDim, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ── IQA result card ───────────────────────────────────────────────────────────

class _IqaResultCard extends StatelessWidget {
  final Map<String, dynamic> result;
  const _IqaResultCard({required this.result});

  double _computeCDI(double b, double n, double piqe) {
    final bScore = math.max(0.0, (1 - b / 100)) * 100;
    final nScore = math.max(0.0, (1 - n /  15)) * 100;
    final pScore = math.max(0.0, (1 - piqe / 100)) * 100;
    return (math.pow(bScore, 0.20) *
        math.pow(nScore, 0.45) *
        math.pow(pScore, 0.35))
        .toDouble();
  }

  Color _qualityColor(double cdi) {
    if (cdi >= 70) return AppTheme.good;
    if (cdi >= 45) return AppTheme.warn;
    return AppTheme.bad;
  }

  @override
  Widget build(BuildContext context) {
    final b    = (result['brisque'] as num?)?.toDouble() ?? 0;
    final n    = (result['niqe']    as num?)?.toDouble() ?? 0;
    final piqe = (result['piqe']    as num?)?.toDouble() ?? 0;
    final cdi  = _computeCDI(b, n, piqe);
    final color = _qualityColor(cdi);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Icon(result['icon'] as IconData? ?? Icons.image_outlined,
                color: AppTheme.iqaColor, size: 20),
            const SizedBox(width: 8),
            Text(result['label'] as String? ?? 'Camera',
                style: const TextStyle(
                    color: AppTheme.textPri,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(
                'Score: ${cdi.toStringAsFixed(1)}',
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          // Metrics row
          Row(children: [
            Expanded(child: _Metric(
                label: 'Sharpness', value: b,
                hint: 'lower = better', color: AppTheme.iqaColor)),
            const SizedBox(width: 8),
            Expanded(child: _Metric(
                label: 'Naturalness', value: n,
                hint: 'lower = better', color: AppTheme.iqaColor)),
            const SizedBox(width: 8),
            Expanded(child: _Metric(
                label: 'Clarity', value: piqe,
                hint: 'lower = better', color: AppTheme.iqaColor)),
          ]),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final double value;
  final String hint;
  final Color  color;
  const _Metric({
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(children: [
        Text(label,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value.toStringAsFixed(2),
            style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        Text(hint,
            style: const TextStyle(
                color: AppTheme.textDim, fontSize: 9)),
      ]),
    );
  }
}

// ── Error box ─────────────────────────────────────────────────────────────────

class _ErrorBox extends StatelessWidget {
  final String        message;
  final VoidCallback? onRetry;
  const _ErrorBox({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bad.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.bad.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message,
              style: const TextStyle(
                  color: AppTheme.bad, fontSize: 12, height: 1.5)),
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onRetry,
              child: const Text('Retry',
                  style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }
}