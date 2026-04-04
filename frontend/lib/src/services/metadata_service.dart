// lib/src/services/metadata_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/app_config.dart';
import '../core/session_store.dart';

class MetadataService {
  MetadataService._();
  static final MetadataService instance = MetadataService._();

  bool _sent = false;

  /// Collect device metadata silently in the background and POST to /device/metadata.
  /// Stores the returned session_id into [SessionStore].
  ///
  /// [testerName]           – display name from Google Sign-In (→ tester_name column).
  ///                          Ignored if [SessionStore.googleDisplayName] is already set.
  /// [questionnaireAnswers] – map with keys matching DB columns exactly:
  ///     'device_usage', 'network_env', 'testing_purpose', 'usage_frequency'.
  ///     Ignored if answers are already in [SessionStore].
  Future<void> collectAndSend({
    String? testerName,
    Map<String, String>? questionnaireAnswers,
    bool includeLocation = false,
  }) async {
    if (_sent) return;
    _sent = true;

    try {
      final payload = await _collectPayload(
        testerName: testerName,
        questionnaireAnswers: questionnaireAnswers,
        includeLocation: includeLocation,
      );

      final response = await http
          .post(
        Uri.parse('${AppConfig.apiBaseUrl}/device/metadata'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final sid = data['session_id'] as String?;
        if (sid != null) {
          SessionStore.instance.setSessionId(sid);
        }
      }
    } catch (e) {
      debugPrint('[MetadataService] silently failed: $e');
    }
  }

  Future<Map<String, dynamic>> _collectPayload({
    String? testerName,
    Map<String, String>? questionnaireAnswers,
    bool includeLocation = false,
  }) async {
    // Screen metrics must be read synchronously on the main thread.
    final screenData = _collectScreenMetrics();

    final futures = [
      _deviceInfo(),              // 0
      _packageInfo(),             // 1
      _batteryInfo(),             // 2
      _networkInfo(),             // 3
      _collectPermissions(),      // 4
      _collectMemoryAndStorage(), // 5
      _collectAudioRoute(),       // 6
      if (includeLocation) _collectLocation(), // 7 (conditional)
    ];

    final results = await Future.wait(futures);

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

    // country_code: prefer ISO code from reverse-geocoding, fall back to locale.
    final geoIso     = location['iso_country_code'] as String?;
    final localeIso  = device['locale_country_code'] as String?;
    final countryCode =
        geoIso ?? (localeIso != null ? '$localeIso(locale)' : null);

    // Device tier derived from RAM + CPU cores.
    final totalRam = memStorage['total_ram_mb'] as int?;
    final cores    = device['cpu_cores'] as int?;
    final tier     = _deriveDeviceTier(totalRam, cores);

    final session = SessionTracker.instance;
    final perf    = PerformanceTracker.instance;

    // SessionStore is the authoritative source for identity + questionnaire.
    // The caller-supplied arguments are used only as fallbacks.
    final store = SessionStore.instance;

    return {
      // ── Tester identity (Google Sign-In) ──────────────────────────────────
      'username':         store.googleDisplayName ?? testerName,
      'user_email':       store.googleEmail,
      'user_photo_url':   store.googlePhotoUrl,

      // ── Questionnaire answers (flat DB column names) ──────────────────────
      'age_group':                  store.ageGroup               ?? questionnaireAnswers?['age_group']                  ?? '',
      'phone_condition':            store.phoneCondition         ?? questionnaireAnswers?['phone_condition']            ?? '',
      'phone_duration':             store.phoneDuration          ?? questionnaireAnswers?['phone_duration']             ?? '',
      'phone_history':              store.phoneHistory           ?? questionnaireAnswers?['phone_history']              ?? '',
      'primary_usage':              store.primaryUsage           ?? questionnaireAnswers?['primary_usage']              ?? '',
      'internet_frequency':         store.internetFrequency      ?? questionnaireAnswers?['internet_frequency']         ?? '',
      'phone_sharing':              store.phoneSharing           ?? questionnaireAnswers?['phone_sharing']              ?? '',
      'internet_connection_type':   store.internetConnectionType ?? questionnaireAnswers?['internet_connection_type']   ?? '',
      'phone_acquisition':          store.phoneAcquisition       ?? questionnaireAnswers?['phone_acquisition']          ?? '',

      // ── Device hardware ───────────────────────────────────────────────────
      'device_model':        device['model'],
      'device_brand':        device['brand'],
      'device_manufacturer': device['manufacturer'],
      'device_product':      device['product'],
      'device_hardware':     device['hardware'],
      'supported_abis':      device['supported_abis'],
      'cpu_cores':           device['cpu_cores'],

      // ── OS & system ───────────────────────────────────────────────────────
      'android_version':      device['android_version'],
      'sdk_version':          device['sdk_version'],
      'build_number':         device['build_number'],
      'security_patch_level': device['security_patch'],
      'build_fingerprint':    device['fingerprint'],
      'bootloader':           device['bootloader'],
      'is_physical_device':   device['is_physical'],
      'is_rooted':            device['is_rooted'],

      // ── App info ──────────────────────────────────────────────────────────
      'app_package_name':      pkg['package_name'],
      'app_version_name':      pkg['version_name'],
      'app_version_code':      pkg['version_code'],
      'app_installer_package': pkg['installer'],
      'is_debug_build':        pkg['is_debug'],

      // ── Screen ────────────────────────────────────────────────────────────
      'screen_width_px':      screenData['width'],
      'screen_height_px':     screenData['height'],
      'screen_density':       screenData['density'],
      'display_refresh_rate': screenData['refresh_rate'],

      // ── Locale & regional ─────────────────────────────────────────────────
      'device_language': device['language'],
      'device_locale':   device['locale'],
      'timezone':        device['timezone'],
      'country_code':    countryCode,

      // ── Battery ───────────────────────────────────────────────────────────
      'battery_level': battery['level'],
      'battery_state': battery['state'],

      // ── Network ───────────────────────────────────────────────────────────
      'connection_type':        network['connection_type'],
      'wifi_name':              network['wifi_name'],
      'wifi_bssid':             network['wifi_bssid'],
      'local_ipv4':             network['local_ipv4'],
      'local_ipv6':             network['local_ipv6'],
      'is_vpn_active':          network['is_vpn'],
      'network_latency_ms':     network['latency_ms'],
      'network_speed_category': network['speed_category'],

      // ── Location (only when includeLocation = true) ───────────────────────
      if (location.isNotEmpty) ...{
        'latitude':          location['latitude'],
        'longitude':         location['longitude'],
        'altitude':          location['altitude'],
        'location_accuracy': location['accuracy'],
        'speed':             location['speed'],
        'bearing':           location['bearing'],
        'locality':          location['locality'],
        'country':           location['country'],
        'postal_code':       location['postal_code'],
        'admin_area':        location['admin_area'],
        'iso_country_code':  location['iso_country_code'],
      },

      // ── Permissions ───────────────────────────────────────────────────────
      'permission_statuses': permissions['statuses'],

      // ── Session activity ──────────────────────────────────────────────────
      'session_start':            session.sessionStart.toIso8601String(),
      'session_screen_views':     session.screenViews,
      'session_user_actions':     session.userActions,
      'session_background_count': session.backgroundCount,

      // ── Performance ───────────────────────────────────────────────────────
      'app_launch_time_ms': perf.launchTimeMs,
      'frame_drop_count':   perf.frameDropCount,
      'last_crash_info':    perf.lastCrashInfo,

      // ── Memory & storage ──────────────────────────────────────────────────
      'device_tier':      tier,
      'total_ram_mb':     memStorage['total_ram_mb'],
      'available_ram_mb': memStorage['available_ram_mb'],
      'total_disk_mb':    memStorage['total_disk_mb'],
      'free_disk_mb':     memStorage['free_disk_mb'],

      // ── Audio ─────────────────────────────────────────────────────────────
      'audio_output_route': audio['route'],
    };
  }

  // ──────────────────────────────────────────────────────────────────
  // Screen — must run on main thread before any async work
  // ──────────────────────────────────────────────────────────────────

  Map<String, double?> _collectScreenMetrics() {
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final physicalSize = view.physicalSize;
      return {
        'width':        physicalSize.width,
        'height':       physicalSize.height,
        'density':      view.devicePixelRatio,
        'refresh_rate': view.display.refreshRate,
      };
    } catch (_) {
      return {'width': null, 'height': null, 'density': null, 'refresh_rate': null};
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Device & OS
  // ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _deviceInfo() async {
    try {
      final di = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info   = await di.androidInfo;
        final locale = Platform.localeName;
        final parts  = locale.split('_');
        return {
          'model':               info.model,
          'brand':               info.brand,
          'manufacturer':        info.manufacturer,
          'product':             info.product,
          'hardware':            info.hardware,
          'supported_abis':      info.supportedAbis.join(', '),
          'cpu_cores':           _cpuCoreCount(),
          'android_version':     info.version.release,
          'sdk_version':         info.version.sdkInt,
          'build_number':        info.id,
          'security_patch':      info.version.securityPatch,
          'fingerprint':         info.fingerprint,
          'bootloader':          info.bootloader,
          'is_physical':         info.isPhysicalDevice,
          'is_rooted':           await _checkRooted(),
          'language':            parts.first,
          'locale':              locale,
          'timezone':            DateTime.now().timeZoneName,
          'locale_country_code': parts.length > 1 ? parts.last : null,
        };
      } else if (Platform.isIOS) {
        final info   = await di.iosInfo;
        final locale = Platform.localeName;
        final parts  = locale.split('_');
        return {
          'model':               info.model,
          'brand':               'Apple',
          'device_name':         info.name,
          'is_physical':         info.isPhysicalDevice,
          'ios_version':         info.systemVersion,
          'language':            parts.first,
          'locale':              locale,
          'timezone':            DateTime.now().timeZoneName,
          'locale_country_code': parts.length > 1 ? parts.last : null,
        };
      }
    } catch (_) {}
    return {};
  }

  // ──────────────────────────────────────────────────────────────────
  // Package / App info
  // ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _packageInfo() async {
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

  // ──────────────────────────────────────────────────────────────────
  // Battery
  // ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _batteryInfo() async {
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

  // ──────────────────────────────────────────────────────────────────
  // Network
  // ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _networkInfo() async {
    try {
      final result  = await Connectivity().checkConnectivity();
      final netInfo = NetworkInfo();

      String? wifiName, wifiBSSID, localIpv4, localIpv6;
      final whenInUse = await Permission.locationWhenInUse.status;
      final fine      = await Permission.location.status;
      if (whenInUse.isGranted || fine.isGranted) {
        wifiName  = (await netInfo.getWifiName())?.replaceAll('"', '');
        wifiBSSID = await netInfo.getWifiBSSID();
        localIpv4 = await netInfo.getWifiIP();
        localIpv6 = await netInfo.getWifiIPv6();
      }

      final latencyMs     = await _measureLatencyMs();
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

  // ──────────────────────────────────────────────────────────────────
  // Location
  // ──────────────────────────────────────────────────────────────────

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
        final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          final p        = marks.first;
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

  // ──────────────────────────────────────────────────────────────────
  // Permissions
  // ──────────────────────────────────────────────────────────────────

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

  // ──────────────────────────────────────────────────────────────────
  // Memory & Storage
  // ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _collectMemoryAndStorage() async {
    int? totalRamMb, availableRamMb, totalDiskMb, freeDiskMb;

    try {
      final memInfo = File('/proc/meminfo').readAsStringSync();
      int? parseKb(String key) {
        final match =
        RegExp('$key:\\s+(\\d+)\\s+kB', multiLine: true).firstMatch(memInfo);
        return match != null ? int.tryParse(match.group(1)!) : null;
      }
      final totalKb     = parseKb('MemTotal');
      final availableKb = parseKb('MemAvailable');
      totalRamMb     = totalKb     != null ? totalKb ~/ 1024     : null;
      availableRamMb = availableKb != null ? availableKb ~/ 1024 : null;
    } catch (_) {}

    try {
      final result = await Process.run('df', ['/data']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).trim().split('\n');
        if (lines.length >= 2) {
          final parts = lines.last.trim().split(RegExp(r'\s+'));
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

  // ──────────────────────────────────────────────────────────────────
  // Audio route
  // ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _collectAudioRoute() async {
    try {
      final result = await Process.run('dumpsys', ['audio']);
      if (result.exitCode == 0) {
        final output = (result.stdout as String).toLowerCase();
        if (output.contains('bluetooth') ||
            output.contains('a2dp') ||
            output.contains('sco')) {
          return {'route': 'bluetooth'};
        }
        if (output.contains('wired_headset') ||
            output.contains('wired_headphone') ||
            output.contains('usb_headset')) {
          return {'route': 'headphone'};
        }
        if (output.contains('earpiece')) return {'route': 'earpiece'};
        if (output.contains('speaker'))  return {'route': 'speaker'};
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

  Future<int?> _measureLatencyMs() async {
    try {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(
        '1.1.1.1',
        53,
        timeout: const Duration(seconds: 3),
      );
      sw.stop();
      socket.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  String _classifyNetworkSpeed(
      List<ConnectivityResult> results, int? latencyMs) {
    if (results.isEmpty || results.first == ConnectivityResult.none) {
      return 'none';
    }
    if (latencyMs == null) return 'unknown';
    if (latencyMs < 80)  return 'fast';
    if (latencyMs < 300) return 'moderate';
    return 'slow';
  }

  String _connectivityLabel(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi))     return 'wifi';
    if (results.contains(ConnectivityResult.mobile))   return 'cellular';
    if (results.contains(ConnectivityResult.ethernet)) return 'ethernet';
    if (results.contains(ConnectivityResult.vpn))      return 'vpn';
    return 'none';
  }

  String _deriveDeviceTier(int? totalRamMb, int? cpuCores) {
    if (totalRamMb == null) return 'unknown';
    if (totalRamMb >= 6144 && (cpuCores ?? 0) >= 8) return 'high';
    if (totalRamMb >= 3072) return 'mid';
    return 'low';
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

// ─────────────────────────────────────────────────────────────────────────────
// SessionTracker — lightweight singleton updated by the app as events occur.
// Wire up in your RouteObserver and WidgetsBindingObserver.
// ─────────────────────────────────────────────────────────────────────────────

class SessionTracker {
  SessionTracker._();
  static final SessionTracker instance = SessionTracker._();

  final DateTime _start = DateTime.now();
  int _screenViews     = 0;
  int _userActions     = 0;
  int _backgroundCount = 0;

  void recordScreenView() => _screenViews++;
  void recordAction()     => _userActions++;
  void recordBackground() => _backgroundCount++;

  DateTime get sessionStart   => _start;
  int get screenViews         => _screenViews;
  int get userActions         => _userActions;
  int get backgroundCount     => _backgroundCount;
}

// ─────────────────────────────────────────────────────────────────────────────
// PerformanceTracker — records launch time, frame drops, and crash info.
// ─────────────────────────────────────────────────────────────────────────────

class PerformanceTracker {
  PerformanceTracker._();
  static final PerformanceTracker instance = PerformanceTracker._();

  final Stopwatch _launchStopwatch = Stopwatch()..start();
  int? _launchTimeMs;
  int  _frameDrops    = 0;
  String? _lastCrashInfo;

  /// Call once Flutter has rendered its first frame:
  ///   SchedulerBinding.instance.addPostFrameCallback((_) =>
  ///       PerformanceTracker.instance.markFirstFrame());
  void markFirstFrame() {
    if (_launchTimeMs == null) {
      _launchStopwatch.stop();
      _launchTimeMs = _launchStopwatch.elapsedMilliseconds;
    }
  }

  void recordFrameDrop()        => _frameDrops++;
  void recordCrash(String info) => _lastCrashInfo = info;

  int? get launchTimeMs    => _launchTimeMs;
  int  get frameDropCount  => _frameDrops;
  String? get lastCrashInfo => _lastCrashInfo;
}