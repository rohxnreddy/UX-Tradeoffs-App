import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';


String? activeSessionId;
class DeviceMeta {
  // ── Device Hardware ──────────────────────────────────────────────
  final String? deviceModel;
  final String? deviceBrand;
  final String? deviceManufacturer;
  final String? deviceProduct;
  final String? deviceHardware;
  final String? supportedAbis;
  final int? cpuCores;

  // ── OS & System ──────────────────────────────────────────────────
  final String? androidVersion;
  final int? sdkVersion;
  final String? buildNumber;
  final String? securityPatchLevel;
  final String? buildFingerprint;
  final String? bootloader;
  final bool? isPhysicalDevice;
  final bool? isRooted;

  // ── App Info ─────────────────────────────────────────────────────
  final String? appPackageName;
  final String? appVersionName;
  final int? appVersionCode;
  final String? appInstallerPackage;
  final bool? isDebugBuild;

  // ── Screen ───────────────────────────────────────────────────────
  final double? screenWidthPx;
  final double? screenHeightPx;
  final double? screenDensity;
  // [7] Display refresh rate — relevant for VMAF video quality judgments.
  final double? displayRefreshRate;

  // ── Locale & Regional ────────────────────────────────────────────
  final String? deviceLanguage;
  final String? deviceLocale;
  final String? timezone;
  final String? countryCode;

  // ── Battery ──────────────────────────────────────────────────────
  final int? batteryLevel;
  final String? batteryState;

  // ── Network ──────────────────────────────────────────────────────
  final String? connectionType;
  final String? wifiName;
  final String? wifiBSSID;
  final String? localIpv4;
  final String? localIpv6;
  final bool? isVpnActive;
  // [3] Network quality — speed category & estimated latency.
  final String? networkSpeedCategory; // 'fast' | 'moderate' | 'slow' | 'none'
  final int? networkLatencyMs;

  // ── Location ─────────────────────────────────────────────────────
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final double? locationAccuracy;
  final double? speed;
  final double? bearing;
  final String? locality;
  final String? country;
  final String? postalCode;
  final String? adminArea;
  final String? isoCountryCode;

  // ── Permissions ──────────────────────────────────────────────────
  final Map<String, String>? permissionStatuses;

  // ── Session ──────────────────────────────────────────────────────
  final DateTime? sessionStart;
  // [1] User behavior — screen views, actions, session duration.
  final int? sessionScreenViews;
  final int? sessionUserActions;
  // [9] App lifecycle events — how many times the app was backgrounded.
  final int? sessionBackgroundCount;

  // ── Performance ──────────────────────────────────────────────────
  // [2] Performance metrics — app launch time, frame drops, crash logs.
  final int? appLaunchTimeMs;
  final int? frameDropCount;
  final String? lastCrashInfo;

  // ── Memory & Storage ─────────────────────────────────────────────
  // [4] Device tier (derived from RAM + CPU).
  final String? deviceTier; // 'high' | 'mid' | 'low'
  // [5] Available RAM — directly affects test viability on constrained devices.
  final int? totalRamMb;
  final int? availableRamMb;
  // [6] Free disk space — prevents silent failures during large quality tests.
  final int? totalDiskMb;
  final int? freeDiskMb;

  // ── Audio ─────────────────────────────────────────────────────────
  // [8] Audio output route — critical context for PESQ/PEAQ scores.
  final String? audioOutputRoute; // 'speaker' | 'earpiece' | 'headphone' | 'bluetooth' | 'unknown'

  const DeviceMeta({
    this.deviceModel,
    this.deviceBrand,
    this.deviceManufacturer,
    this.deviceProduct,
    this.deviceHardware,
    this.supportedAbis,
    this.cpuCores,
    this.androidVersion,
    this.sdkVersion,
    this.buildNumber,
    this.securityPatchLevel,
    this.buildFingerprint,
    this.bootloader,
    this.isPhysicalDevice,
    this.isRooted,
    this.appPackageName,
    this.appVersionName,
    this.appVersionCode,
    this.appInstallerPackage,
    this.isDebugBuild,
    this.screenWidthPx,
    this.screenHeightPx,
    this.screenDensity,
    this.displayRefreshRate,
    this.deviceLanguage,
    this.deviceLocale,
    this.timezone,
    this.countryCode,
    this.batteryLevel,
    this.batteryState,
    this.connectionType,
    this.wifiName,
    this.wifiBSSID,
    this.localIpv4,
    this.localIpv6,
    this.isVpnActive,
    this.networkSpeedCategory,
    this.networkLatencyMs,
    this.latitude,
    this.longitude,
    this.altitude,
    this.locationAccuracy,
    this.speed,
    this.bearing,
    this.locality,
    this.country,
    this.postalCode,
    this.adminArea,
    this.isoCountryCode,
    this.permissionStatuses,
    this.sessionStart,
    this.sessionScreenViews,
    this.sessionUserActions,
    this.sessionBackgroundCount,
    this.appLaunchTimeMs,
    this.frameDropCount,
    this.lastCrashInfo,
    this.deviceTier,
    this.totalRamMb,
    this.availableRamMb,
    this.totalDiskMb,
    this.freeDiskMb,
    this.audioOutputRoute,
  });

  Map<String, dynamic> toJson() => {
    // Device
    'device_model': deviceModel,
    'device_brand': deviceBrand,
    'device_manufacturer': deviceManufacturer,
    'device_product': deviceProduct,
    'device_hardware': deviceHardware,
    'supported_abis': supportedAbis,
    'cpu_cores': cpuCores,
    // OS
    'android_version': androidVersion,
    'sdk_version': sdkVersion,
    'build_number': buildNumber,
    'security_patch_level': securityPatchLevel,
    'build_fingerprint': buildFingerprint,
    'bootloader': bootloader,
    'is_physical_device': isPhysicalDevice,
    'is_rooted': isRooted,
    // App
    'app_package_name': appPackageName,
    'app_version_name': appVersionName,
    'app_version_code': appVersionCode,
    'app_installer_package': appInstallerPackage,
    'is_debug_build': isDebugBuild,
    // Screen
    'screen_width_px': screenWidthPx,
    'screen_height_px': screenHeightPx,
    'screen_density': screenDensity,
    'display_refresh_rate': displayRefreshRate,
    // Locale
    'device_language': deviceLanguage,
    'device_locale': deviceLocale,
    'timezone': timezone,
    'country_code': countryCode,
    // Battery
    'battery_level': batteryLevel,
    'battery_state': batteryState,
    // Network
    'connection_type': connectionType,
    'wifi_name': wifiName,
    'wifi_bssid': wifiBSSID,
    'local_ipv4': localIpv4,
    'local_ipv6': localIpv6,
    'is_vpn_active': isVpnActive,
    'network_speed_category': networkSpeedCategory,
    'network_latency_ms': networkLatencyMs,
    // Location
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'location_accuracy': locationAccuracy,
    'speed': speed,
    'bearing': bearing,
    'locality': locality,
    'country': country,
    'postal_code': postalCode,
    'admin_area': adminArea,
    'iso_country_code': isoCountryCode,
    // Permissions
    'permission_statuses': permissionStatuses,
    // Session
    'session_start': sessionStart?.toIso8601String(),
    'session_screen_views': sessionScreenViews,
    'session_user_actions': sessionUserActions,
    'session_background_count': sessionBackgroundCount,
    // Performance
    'app_launch_time_ms': appLaunchTimeMs,
    'frame_drop_count': frameDropCount,
    'last_crash_info': lastCrashInfo,
    // Memory & Storage
    'device_tier': deviceTier,
    'total_ram_mb': totalRamMb,
    'available_ram_mb': availableRamMb,
    'total_disk_mb': totalDiskMb,
    'free_disk_mb': freeDiskMb,
    // Audio
    'audio_output_route': audioOutputRoute,
  };
}

String _apiBaseUrl = 'http://192.168.0.100:8000';
Future<void> sendMetadata(DeviceMeta meta) async {
  final response = await http.post(
    Uri.parse('$_apiBaseUrl/device/metadata'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(meta.toJson()),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to send metadata: ${response.body}');
  }
  // Parse and save session_id for all subsequent requests
  final data = jsonDecode(response.body);
  final sessionId = data['session_id'] as String?;
  if (sessionId != null) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('session_id', sessionId);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session tracker — a lightweight singleton updated by the app as events occur.
// Wire it up in your route observer and lifecycle mixin.
// ─────────────────────────────────────────────────────────────────────────────

class SessionTracker {
  SessionTracker._();
  static final SessionTracker instance = SessionTracker._();

  final DateTime _start = DateTime.now();
  int _screenViews = 0;
  int _userActions = 0;
  int _backgroundCount = 0;

  // Call from your RouteObserver.didPush / didReplace.
  void recordScreenView() => _screenViews++;

  // Call on significant user interactions (button taps, form submits, etc.).
  void recordAction() => _userActions++;

  // Call from AppLifecycleListener / WidgetsBindingObserver when app is paused.
  void recordBackground() => _backgroundCount++;

  DateTime get sessionStart => _start;
  int get screenViews => _screenViews;
  int get userActions => _userActions;
  int get backgroundCount => _backgroundCount;
}

// ─────────────────────────────────────────────────────────────────────────────
// Performance tracker — records launch time, frame drops, and crash info.
// ─────────────────────────────────────────────────────────────────────────────

class PerformanceTracker {
  PerformanceTracker._();
  static final PerformanceTracker instance = PerformanceTracker._();

  // Stopwatch started at process entry (call markLaunchStart() in main()).
  final Stopwatch _launchStopwatch = Stopwatch()..start();
  int? _launchTimeMs;
  int _frameDrops = 0;
  String? _lastCrashInfo;

  // Call once Flutter has rendered its first frame:
  //   SchedulerBinding.instance.addPostFrameCallback((_) => PerformanceTracker.instance.markFirstFrame());
  void markFirstFrame() {
    if (_launchTimeMs == null) {
      _launchStopwatch.stop();
      _launchTimeMs = _launchStopwatch.elapsedMilliseconds;
    }
  }

  // Call from a SchedulerBinding frame callback when frame budget is exceeded.
  // Simple heuristic: flag a drop if a frame took > 16 ms (60 fps budget).
  void recordFrameDrop() => _frameDrops++;

  // Call from FlutterError.onError or PlatformDispatcher.instance.onError.
  void recordCrash(String info) => _lastCrashInfo = info;

  int? get launchTimeMs => _launchTimeMs;
  int get frameDropCount => _frameDrops;
  String? get lastCrashInfo => _lastCrashInfo;
}

/// Central service to collect all metadata.
class MetaCollector {
  MetaCollector._();
  static final MetaCollector instance = MetaCollector._();

  // ──────────────────────────────────────────────────────────────────
  // Public entry point
  // ──────────────────────────────────────────────────────────────────

  // Permanently cached Future — never cleared after completion.
  // This guarantees that no matter how many times collect() is called
  // (concurrent, sequential, new widget instances), exactly one _doCollect()
  // runs and exactly one sendMetadata() fires per app session.
  //
  // Pull-to-refresh in MetaPage uses _doCollect() directly and does NOT
  // call sendMetadata(), so skipping the cache there is intentional.
  Future<DeviceMeta>? _collectFuture;

  /// Returns metadata for this session.
  ///
  /// The first call starts collection (including GPS if [includeLocation] is
  /// true). Every subsequent call — from any widget or service — receives the
  /// same Future, so only one DB row is ever written.
  ///
  /// For manual refresh (no DB write), call [collectFresh] instead.
  Future<DeviceMeta> collect({bool includeLocation = false}) =>
      _collectFuture ??= _doCollect(includeLocation: includeLocation);

  /// Runs a fresh collection without touching the session cache or sending
  /// to the server. Used by pull-to-refresh in MetaPage.
  Future<DeviceMeta> collectFresh({bool includeLocation = false}) =>
      _doCollect(includeLocation: includeLocation);

  Future<DeviceMeta> _doCollect({bool includeLocation = false}) async {
    // Screen metrics must be read synchronously on the main thread.
    final screenData = _collectScreenMetrics();

    // Everything else runs in parallel.
    final results = await Future.wait([
      _collectDeviceInfo(),
      _collectPackageInfo(),
      _collectBattery(),
      _collectNetwork(),
      _collectPermissions(),
      _collectMemoryAndStorage(),
      _collectAudioRoute(),
      if (includeLocation) _collectLocation(),
    ]);

    final device      = results[0] as Map<String, dynamic>;
    final pkg         = results[1] as Map<String, dynamic>;
    final battery     = results[2] as Map<String, dynamic>;
    final network     = results[3] as Map<String, dynamic>;
    final permissions = results[4] as Map<String, dynamic>;
    final memStorage  = results[5] as Map<String, dynamic>;
    final audio       = results[6] as Map<String, dynamic>;
    final location    = includeLocation
        ? results[7] as Map<String, dynamic>
        : <String, dynamic>{};

    // country_code: prefer the ISO code from reverse-geocoding (real geography).
    final geoIso    = location['iso_country_code'] as String?;
    final localeIso = device['locale_country_code'] as String?;
    final countryCode =
        geoIso ?? (localeIso != null ? '$localeIso(locale)' : null);

    // Device tier derived from RAM + CPU cores.
    final totalRam = memStorage['total_ram_mb'] as int?;
    final cores    = device['cpu_cores'] as int?;
    final tier     = _deriveDeviceTier(totalRam, cores);

    final session = SessionTracker.instance;
    final perf    = PerformanceTracker.instance;

    return DeviceMeta(
      // Device
      deviceModel:        device['model'],
      deviceBrand:        device['brand'],
      deviceManufacturer: device['manufacturer'],
      deviceProduct:      device['product'],
      deviceHardware:     device['hardware'],
      supportedAbis:      device['supported_abis'],
      cpuCores:           device['cpu_cores'],
      // OS
      androidVersion:     device['android_version'],
      sdkVersion:         device['sdk_version'],
      buildNumber:        device['build_number'],
      securityPatchLevel: device['security_patch'],
      buildFingerprint:   device['fingerprint'],
      bootloader:         device['bootloader'],
      isPhysicalDevice:   device['is_physical'],
      isRooted:           device['is_rooted'],
      // App
      appPackageName:     pkg['package_name'],
      appVersionName:     pkg['version_name'],
      appVersionCode:     pkg['version_code'],
      appInstallerPackage: pkg['installer'],
      isDebugBuild:       pkg['is_debug'],
      // Screen
      screenWidthPx:      screenData['width'],
      screenHeightPx:     screenData['height'],
      screenDensity:      screenData['density'],
      displayRefreshRate: screenData['refresh_rate'],
      // Locale
      deviceLanguage: device['language'],
      deviceLocale:   device['locale'],
      timezone:       device['timezone'],
      countryCode:    countryCode,
      // Battery
      batteryLevel: battery['level'],
      batteryState: battery['state'],
      // Network
      connectionType:       network['connection_type'],
      wifiName:             network['wifi_name'],
      wifiBSSID:            network['wifi_bssid'],
      localIpv4:            network['local_ipv4'],
      localIpv6:            network['local_ipv6'],
      isVpnActive:          network['is_vpn'],
      networkSpeedCategory: network['speed_category'],
      networkLatencyMs:     network['latency_ms'],
      // Location
      latitude:         location['latitude'],
      longitude:        location['longitude'],
      altitude:         location['altitude'],
      locationAccuracy: location['accuracy'],
      speed:            location['speed'],
      bearing:          location['bearing'],
      locality:         location['locality'],
      country:          location['country'],
      postalCode:       location['postal_code'],
      adminArea:        location['admin_area'],
      isoCountryCode:   location['iso_country_code'],
      // Permissions
      permissionStatuses: Map<String, String>.from(
          permissions['statuses'] as Map? ?? {}),
      // Session
      sessionStart:         session.sessionStart,
      sessionScreenViews:   session.screenViews,
      sessionUserActions:   session.userActions,
      sessionBackgroundCount: session.backgroundCount,
      // Performance
      appLaunchTimeMs: perf.launchTimeMs,
      frameDropCount:  perf.frameDropCount,
      lastCrashInfo:   perf.lastCrashInfo,
      // Memory & Storage
      deviceTier:     tier,
      totalRamMb:     memStorage['total_ram_mb'],
      availableRamMb: memStorage['available_ram_mb'],
      totalDiskMb:    memStorage['total_disk_mb'],
      freeDiskMb:     memStorage['free_disk_mb'],
      // Audio
      audioOutputRoute: audio['route'],
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────────────

  /// Reads physical screen size and refresh rate from WidgetsBinding.
  Map<String, double?> _collectScreenMetrics() {
    try {
      // PlatformDispatcher.views gives us the real FlutterView objects,
      // which expose .physicalSize, .devicePixelRatio, and .display.refreshRate
      // without any deprecated API.
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final physicalSize = view.physicalSize;
      final dpr          = view.devicePixelRatio;
      // display.refreshRate is the correct, non-deprecated path (Flutter ≥ 3.7).
      final refreshRate  = view.display.refreshRate;
      return {
        'width':        physicalSize.width,
        'height':       physicalSize.height,
        'density':      dpr,
        'refresh_rate': refreshRate,
      };
    } catch (_) {
      return {'width': null, 'height': null, 'density': null, 'refresh_rate': null};
    }
  }

  Future<Map<String, dynamic>> _collectDeviceInfo() async {
    try {
      final di   = DeviceInfoPlugin();
      final info = await di.androidInfo;
      final locale = Platform.localeName;

      final parts         = locale.split('_');
      final language      = parts.first;
      final localeCountry = parts.length > 1 ? parts.last : null;

      return {
        'model':              info.model,
        'brand':              info.brand,
        'manufacturer':       info.manufacturer,
        'product':            info.product,
        'hardware':           info.hardware,
        'supported_abis':     info.supportedAbis.join(', '),
        'cpu_cores':          _cpuCoreCount(),
        'android_version':    info.version.release,
        'sdk_version':        info.version.sdkInt,
        'build_number':       info.id,
        'security_patch':     info.version.securityPatch,
        'fingerprint':        info.fingerprint,
        'bootloader':         info.bootloader,
        'is_physical':        info.isPhysicalDevice,
        'is_rooted':          await _checkRooted(),
        'language':           language,
        'locale':             locale,
        'timezone':           DateTime.now().timeZoneName,
        'locale_country_code': localeCountry,
      };
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> _collectPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return {
        'package_name': info.packageName,
        'version_name': info.version,
        'version_code': int.tryParse(info.buildNumber),
        'installer':    info.installerStore,
        'is_debug':     _isDebug(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> _collectBattery() async {
    try {
      final battery = Battery();
      final level   = await battery.batteryLevel;
      final state   = await battery.batteryState;
      return {
        'level': level,
        'state': state.name,
      };
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> _collectNetwork() async {
    try {
      final connectivity = Connectivity();
      final result       = await connectivity.checkConnectivity();
      final netInfo      = NetworkInfo();

      String? wifiName, wifiBSSID, localIpv4, localIpv6;

      final whenInUse = await Permission.locationWhenInUse.status;
      final fine      = await Permission.location.status;
      if (whenInUse.isGranted || fine.isGranted) {
        wifiName = (await netInfo.getWifiName())?.replaceAll('"', '');
        wifiBSSID = await netInfo.getWifiBSSID();
        localIpv4 = await netInfo.getWifiIP();
        localIpv6 = await netInfo.getWifiIPv6();
      }

      // [3] Measure latency with a lightweight ICMP-style TCP probe.
      final latencyMs = await _measureLatencyMs();
      final speedCategory = _classifyNetworkSpeed(result, latencyMs);

      return {
        'connection_type': _connectivityLabel(result),
        'wifi_name':       wifiName,
        'wifi_bssid':      wifiBSSID,
        'local_ipv4':      localIpv4,
        'local_ipv6':      localIpv6,
        'is_vpn':          await _detectVpn(),
        'latency_ms':      latencyMs,
        'speed_category':  speedCategory,
      };
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> _collectLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return {'_location_error': 'service_disabled'};

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return {'_location_error': 'permission_${permission.name}'};
      }

      // LocationAccuracy.high requires GPS satellite lock and hangs indefinitely
      // without timeLimit. Use medium + 10 s timeout, fall back to last known.
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 10),
        );
      } on TimeoutException {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) return {'_location_error': 'no_position_available'};

      String? locality, country, postalCode, adminArea, isoCountryCode;
      try {
        final marks =
        await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          final p       = marks.first;
          locality       = p.locality;
          country        = p.country;
          postalCode     = p.postalCode;
          adminArea      = p.administrativeArea;
          isoCountryCode = p.isoCountryCode;
        }
      } catch (_) {}

      return {
        'latitude':         pos.latitude,
        'longitude':        pos.longitude,
        'altitude':         pos.altitude,
        'accuracy':         pos.accuracy,
        'speed':            pos.speed,
        'bearing':          pos.heading,
        'locality':         locality,
        'country':          country,
        'postal_code':      postalCode,
        'admin_area':       adminArea,
        'iso_country_code': isoCountryCode,
      };
    } catch (e) {
      return {'_location_error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _collectPermissions() async {
    final permissions = [
      Permission.location,
      Permission.locationWhenInUse,
      Permission.camera,
      Permission.microphone,
      Permission.storage,
      Permission.photos,
      Permission.notification,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.activityRecognition,
      Permission.sensors,
    ];

    final statuses = <String, String>{};
    for (final p in permissions) {
      try {
        final status = await p.status;
        statuses[p.toString()] = status.name;
      } catch (_) {
        statuses[p.toString()] = 'unknown';
      }
    }

    return {'statuses': statuses};
  }

  /// [4][5][6] Collects RAM and disk statistics from /proc/meminfo and
  /// dart:io StatFs. No plugins required — works on any Android Flutter app.
  Future<Map<String, dynamic>> _collectMemoryAndStorage() async {
    int? totalRamMb, availableRamMb, totalDiskMb, freeDiskMb;

    // RAM via /proc/meminfo (available on all Android versions).
    try {
      final memInfo = File('/proc/meminfo').readAsStringSync();
      int? parseKb(String key) {
        final match = RegExp('$key:\\s+(\\d+)\\s+kB', multiLine: true)
            .firstMatch(memInfo);
        return match != null ? int.tryParse(match.group(1)!) : null;
      }
      final totalKb     = parseKb('MemTotal');
      final availableKb = parseKb('MemAvailable');
      totalRamMb     = totalKb     != null ? totalKb ~/ 1024     : null;
      availableRamMb = availableKb != null ? availableKb ~/ 1024 : null;
    } catch (_) {}

    // Disk via dart:io — reads the internal storage partition.
    try {
      final stat = await FileStat.stat('/data');
      // FileStat doesn't expose block counts; use a /proc/mounts parse instead.
      // Simpler cross-version approach: read df output via Process.
      final result = await Process.run('df', ['/data']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).trim().split('\n');
        if (lines.length >= 2) {
          final parts = lines.last.trim().split(RegExp(r'\s+'));
          // df columns: Filesystem, 1K-blocks, Used, Available, Use%, Mounted
          if (parts.length >= 4) {
            final totalKb = int.tryParse(parts[1]);
            final freeKb  = int.tryParse(parts[3]);
            totalDiskMb = totalKb != null ? totalKb ~/ 1024 : null;
            freeDiskMb  = freeKb  != null ? freeKb  ~/ 1024 : null;
          }
        }
      }
    } catch (_) {}

    return {
      'total_ram_mb':     totalRamMb,
      'available_ram_mb': availableRamMb,
      'total_disk_mb':    totalDiskMb,
      'free_disk_mb':     freeDiskMb,
    };
  }

  /// [8] Detects the current audio output route by inspecting Android audio
  /// routing via /proc or a lightweight shell command.
  /// Returns: 'speaker' | 'earpiece' | 'headphone' | 'bluetooth' | 'unknown'
  Future<Map<String, dynamic>> _collectAudioRoute() async {
    try {
      // Android exposes the active audio device in /proc/asound/cards or
      // via `dumpsys audio`. The dumpsys approach is the most reliable.
      final result = await Process.run('dumpsys', ['audio']);
      if (result.exitCode == 0) {
        final output = (result.stdout as String).toLowerCase();
        // Look for the active output device string in dumpsys audio output.
        if (output.contains('bluetooth') || output.contains('a2dp') ||
            output.contains('sco')) {
          return {'route': 'bluetooth'};
        }
        if (output.contains('wired_headset') ||
            output.contains('wired_headphone') ||
            output.contains('usb_headset')) {
          return {'route': 'headphone'};
        }
        if (output.contains('earpiece')) {
          return {'route': 'earpiece'};
        }
        if (output.contains('speaker')) {
          return {'route': 'speaker'};
        }
      }
    } catch (_) {}
    return {'route': 'unknown'};
  }

  // ──────────────────────────────────────────────────────────────────
  // Utility helpers
  // ──────────────────────────────────────────────────────────────────

  int? _cpuCoreCount() {
    try {
      final cpuInfo = File('/proc/cpuinfo').readAsStringSync();
      return RegExp(r'^processor', multiLine: true).allMatches(cpuInfo).length;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _checkRooted() async {
    const paths = [
      '/sbin/su',
      '/system/bin/su',
      '/system/xbin/su',
      '/data/local/xbin/su',
      '/data/local/bin/su',
      '/system/sd/xbin/su',
      '/system/bin/failsafe/su',
    ];
    for (final path in paths) {
      if (await File(path).exists()) return true;
    }
    return false;
  }

  Future<bool> _detectVpn() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.startsWith('tun') ||
            name.startsWith('ppp') ||
            name.startsWith('tap')) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// [3] Estimates round-trip latency by opening a TCP socket to a reliable
  /// host (Cloudflare DNS) and measuring the connection time.
  Future<int?> _measureLatencyMs() async {
    try {
      final stopwatch = Stopwatch()..start();
      final socket = await Socket.connect(
        '1.1.1.1',
        53,
        timeout: const Duration(seconds: 3),
      );
      stopwatch.stop();
      socket.destroy();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  /// [3] Classifies network speed based on connectivity type and measured
  /// latency. This gives a coarse quality tier without needing a speed test.
  String _classifyNetworkSpeed(
      List<ConnectivityResult> results, int? latencyMs) {
    if (results.isEmpty || results.first == ConnectivityResult.none) {
      return 'none';
    }
    if (latencyMs == null) return 'unknown';
    if (latencyMs < 80)  return 'fast';    // Typical WiFi / 4G
    if (latencyMs < 300) return 'moderate'; // Edge 3G, congested WiFi
    return 'slow';                          // 2G or very poor signal
  }

  /// [4] Derives a device tier from total RAM and CPU core count.
  /// Thresholds are calibrated for Android phones (A30s = low tier).
  String _deriveDeviceTier(int? totalRamMb, int? cpuCores) {
    if (totalRamMb == null) return 'unknown';
    if (totalRamMb >= 6144 && (cpuCores ?? 0) >= 8) return 'high';
    if (totalRamMb >= 3072) return 'mid';
    return 'low';
  }

  String _connectivityLabel(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi))     return 'wifi';
    if (results.contains(ConnectivityResult.mobile))   return 'cellular';
    if (results.contains(ConnectivityResult.ethernet)) return 'ethernet';
    if (results.contains(ConnectivityResult.vpn))      return 'vpn';
    return 'none';
  }

  bool _isDebug() {
    bool debug = false;
    assert(() {
      debug = true;
      return true;
    }());
    return debug;
  }
}