import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Holds all collected device & user metadata.
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

  // ── Locale & Regional ────────────────────────────────────────────
  final String? deviceLanguage;
  final String? deviceLocale;
  final String? timezone;
  // NOTE: countryCode comes from reverse-geocoded location (real geography),
  // NOT from device locale (which reflects language preference, not geography).
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
  final String? isoCountryCode; // e.g. "IN", "US" — from geocoding

  // ── Permissions ──────────────────────────────────────────────────
  final Map<String, String>? permissionStatuses;

  // ── Session ──────────────────────────────────────────────────────
  final DateTime? sessionStart;

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
  };
}

/// Central service to collect all metadata.
class MetaCollector {
  MetaCollector._();
  static final MetaCollector instance = MetaCollector._();

  // ──────────────────────────────────────────────────────────────────
  // Public entry point
  // ──────────────────────────────────────────────────────────────────

  /// Collects all available metadata.
  ///
  /// [includeLocation] — pass true only after the user has been
  /// informed; triggers the system GPS permission prompt if needed.
  Future<DeviceMeta> collect({bool includeLocation = false}) async {
    // Screen metrics must be read synchronously on the main thread.
    final screenData = _collectScreenMetrics();

    // Everything else runs in parallel.
    final results = await Future.wait([
      _collectDeviceInfo(),
      _collectPackageInfo(),
      _collectBattery(),
      _collectNetwork(),
      _collectPermissions(),
      if (includeLocation) _collectLocation(),
    ]);

    final device      = results[0] as Map<String, dynamic>;
    final pkg         = results[1] as Map<String, dynamic>;
    final battery     = results[2] as Map<String, dynamic>;
    final network     = results[3] as Map<String, dynamic>;
    final permissions = results[4] as Map<String, dynamic>;
    final location    = includeLocation
        ? results[5] as Map<String, dynamic>
        : <String, dynamic>{};

    // country_code: prefer the ISO code from reverse-geocoding (real geography).
    // Fall back to the locale suffix only when location is unavailable — and
    // tag it so callers know it is locale-derived, not geography-derived.
    final geoIso    = location['iso_country_code'] as String?;
    final localeIso = device['locale_country_code'] as String?;
    final countryCode =
        geoIso ?? (localeIso != null ? '$localeIso(locale)' : null);

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
      // Screen — from WidgetsBinding.instance.window (fixes null values)
      screenWidthPx:  screenData['width'],
      screenHeightPx: screenData['height'],
      screenDensity:  screenData['density'],
      // Locale
      deviceLanguage: device['language'],
      deviceLocale:   device['locale'],
      timezone:       device['timezone'],
      countryCode:    countryCode,
      // Battery
      batteryLevel: battery['level'],
      batteryState: battery['state'],
      // Network
      connectionType: network['connection_type'],
      wifiName:       network['wifi_name'],
      wifiBSSID:      network['wifi_bssid'],
      localIpv4:      network['local_ipv4'],
      localIpv6:      network['local_ipv6'],
      isVpnActive:    network['is_vpn'],
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
      sessionStart: DateTime.now(),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────────────

  /// FIX: reads physical screen size from WidgetsBinding.
  /// Works without a BuildContext, always available after runApp().
  Map<String, double?> _collectScreenMetrics() {
    try {
      // ignore: deprecated_member_use
      final view = WidgetsBinding.instance.window;
      final physicalSize = view.physicalSize;
      final dpr = view.devicePixelRatio;
      return {
        'width':   physicalSize.width,
        'height':  physicalSize.height,
        'density': dpr,
      };
    } catch (_) {
      return {'width': null, 'height': null, 'density': null};
    }
  }

  Future<Map<String, dynamic>> _collectDeviceInfo() async {
    try {
      final di   = DeviceInfoPlugin();
      final info = await di.androidInfo;
      final locale = Platform.localeName; // e.g. "en_IN" or "en_GB"

      // Split safely — some locales are just "en" with no underscore.
      final parts         = locale.split('_');
      final language      = parts.first;
      // Do NOT use this as the real country — it reflects language settings.
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
        // Kept separate so collect() can label it as locale-derived.
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
        'state': state.name, // charging / discharging / full / unknown
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

      // WiFi SSID/BSSID/IP require ACCESS_FINE_LOCATION on Android 8.1+.
      // Check both variants because permission_handler and geolocator manage
      // separate runtime state on some devices.
      final whenInUse = await Permission.locationWhenInUse.status;
      final fine      = await Permission.location.status;
      if (whenInUse.isGranted || fine.isGranted) {
        wifiName  = await netInfo.getWifiName();
        wifiBSSID = await netInfo.getWifiBSSID();
        localIpv4 = await netInfo.getWifiIP();
        localIpv6 = await netInfo.getWifiIPv6();
      }

      return {
        'connection_type': _connectivityLabel(result),
        'wifi_name':       wifiName,
        'wifi_bssid':      wifiBSSID,
        'local_ipv4':      localIpv4,
        'local_ipv6':      localIpv6,
        'is_vpn':          await _detectVpn(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> _collectLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return {};

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return {};
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

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
          isoCountryCode = p.isoCountryCode; // "IN" — accurate geography
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
    } catch (_) {
      return {};
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

  // ──────────────────────────────────────────────────────────────────
  // Utility helpers
  // ──────────────────────────────────────────────────────────────────

  /// Counts physical CPU cores by reading /proc/cpuinfo.
  int? _cpuCoreCount() {
    try {
      final cpuInfo = File('/proc/cpuinfo').readAsStringSync();
      return RegExp(r'^processor', multiLine: true).allMatches(cpuInfo).length;
    } catch (_) {
      return null;
    }
  }

  /// Heuristic rooted check — not 100% guaranteed.
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

  /// Detects an active VPN by scanning network interface names.
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