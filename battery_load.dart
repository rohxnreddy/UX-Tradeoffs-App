import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';
import 'package:torch_light/torch_light.dart';
import 'package:camera/camera.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:screen_brightness/screen_brightness.dart';

List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const ExtremeApp());
}

class ExtremeApp extends StatelessWidget {
  const ExtremeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: ExtremeHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ExtremeHome extends StatefulWidget {
  const ExtremeHome({super.key});

  @override
  State<ExtremeHome> createState() => _ExtremeHomeState();
}

class _ExtremeHomeState extends State<ExtremeHome>
    with SingleTickerProviderStateMixin {
  CameraController? cameraController;
  AudioPlayer player = AudioPlayer();
  Battery battery = Battery();

  bool running = false; ,mx 
  int batteryLevel = 0;
  Timer? networkTimer;
  Timer? vibrationTimer;
  Timer? batteryTimer;
  // late Ticker ticker;

  @override
  void initState() {
    super.initState();
    // ticker = Ticker((_) {
    //   setState(() {});
    // })..start();
  }

  // ================= CPU BURN =================

  void cpuBurn(_) {
    while (true) {
      double x = 0;
      for (int i = 0; i < 20000000; i++) {
        x += i * 0.7;
      }
    }
  }

  Future<void> startCpuBurn() async {
    int cores = Platform.numberOfProcessors;
    for (int i = 0; i < cores; i++) {
      Isolate.spawn(cpuBurn, null);
    }
  }

  // ================= NETWORK SPAM =================

  void startNetworkSpam() {
    networkTimer =
        Timer.periodic(const Duration(milliseconds: 100), (_) {
      http.get(Uri.parse("https://speed.hetzner.de/100MB.bin"));
    });
  }

  // ================= SENSORS =================

  void startSensors() {
    accelerometerEvents.listen((event) {});
    gyroscopeEvents.listen((event) {});
    userAccelerometerEvents.listen((event) {});
  }

  // ================= GPS =================

  void startGPS() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen((event) {});
  }

  // ================= VIBRATION =================

  void startVibration() {
    vibrationTimer =
        Timer.periodic(const Duration(seconds: 1), (_) async {
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(duration: 800);
      }
    });
  }

  // ================= AUDIO =================

  Future<void> startAudio() async {
    await player.setReleaseMode(ReleaseMode.loop);
    await player.play(AssetSource('')); // Add your own loud mp3 asset
  }

  // ================= BRIGHTNESS =================

  Future<void> setMaxBrightness() async {
    await ScreenBrightness().setScreenBrightness(1.0);
  }

  // ================= FLASHLIGHT =================

  Future<void> startFlash() async {
    try {
      await TorchLight.enableTorch();
    } catch (_) {}
  }

  // ================= CAMERA =================

  Future<void> startCamera() async {
    cameraController =
        CameraController(cameras.first, ResolutionPreset.max);
    await cameraController!.initialize();
    setState(() {});
  }

  // ================= BATTERY MONITOR =================

  void startBatteryMonitor() {
    batteryTimer =
        Timer.periodic(const Duration(seconds: 5), (_) async {
      int level = await battery.batteryLevel;
      setState(() {
        batteryLevel = level;
      });
    });
  }

  // ================= START ALL =================

  Future<void> startExtremeMode() async {
    setState(() {
      running = true;
    });

    await startCpuBurn();
    startNetworkSpam();
    startSensors();
    startGPS();
    startVibration();
    await setMaxBrightness();
    await startFlash();
    await startCamera();
    startBatteryMonitor();
  }

  @override
  void dispose() {
    networkTimer?.cancel();
    vibrationTimer?.cancel();
    batteryTimer?.cancel();
    player.dispose();
    cameraController?.dispose();
    // ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: running
          ? Stack(
              children: [
                if (cameraController != null &&
                    cameraController!.value.isInitialized)
                  CameraPreview(cameraController!),
                CustomPaint(
                  painter: HeavyPainter(),
                  size: MediaQuery.of(context).size,
                ),
                Positioned(
                  top: 40,
                  left: 20,
                  child: Text(
                    "Battery: $batteryLevel%",
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.red),
                  ),
                )
              ],
            )
          : Center(
              child: ElevatedButton(
                onPressed: startExtremeMode,
                child: const Text("START EXTREME MODE"),
              ),
            ),
    );
  }
}

// ================= GPU HEAVY PAINTER =================

class HeavyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    for (int i = 0; i < 30000; i++) {
      paint.color = Colors.primaries[i % Colors.primaries.length];
      canvas.drawCircle(
        Offset(
          (i * 17) % size.width,
          (i * 31) % size.height,
        ),
        6,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}