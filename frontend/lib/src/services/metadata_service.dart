// lib/src/services/metadata_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
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
  Future<void> collectAndSend({
    String? testerName,
    Map<String, String>? questionnaireAnswers,
  }) async {
    if (_sent) return;
    _sent = true;

    try {
      final payload = await _collectPayload(
        testerName: testerName,
        questionnaireAnswers: questionnaireAnswers,
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
  }) async {
    final results = await Future.wait([
      _deviceInfo(),
      _packageInfo(),
      _batteryInfo(),
      _networkInfo(),
    ]);

    return {
      ...results[0],
      ...results[1],
      ...results[2],
      ...results[3],
      if (testerName != null) 'tester_name': testerName,
      if (questionnaireAnswers != null) 'questionnaire': questionnaireAnswers,
      'collected_at': DateTime.now().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> _deviceInfo() async {
    try {
      final di = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await di.androidInfo;
        return {
          'device_model':        info.model,
          'device_brand':        info.brand,
          'device_manufacturer': info.manufacturer,
          'android_version':     info.version.release,
          'sdk_version':         info.version.sdkInt,
          'is_physical_device':  info.isPhysicalDevice,
        };
      } else if (Platform.isIOS) {
        final info = await di.iosInfo;
        return {
          'device_model':       info.model,
          'device_name':        info.name,
          'system_version':     info.systemVersion,
          'is_physical_device': info.isPhysicalDevice,
        };
      }
    } catch (_) {}
    return {};
  }

  Future<Map<String, dynamic>> _packageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return {
        'app_package_name': info.packageName,
        'app_version':      info.version,
        'app_build_number': info.buildNumber,
      };
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> _batteryInfo() async {
    try {
      final battery = Battery();
      final level   = await battery.batteryLevel;
      final state   = await battery.batteryState;
      return {
        'battery_level': level,
        'battery_state': state.name,
      };
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> _networkInfo() async {
    try {
      final result  = await Connectivity().checkConnectivity();
      final netInfo = NetworkInfo();
      String? wifiName;
      final whenInUse = await Permission.locationWhenInUse.status;
      if (whenInUse.isGranted) {
        wifiName = (await netInfo.getWifiName())?.replaceAll('"', '');
      }
      String connType = 'none';
      if (result.contains(ConnectivityResult.wifi))   connType = 'wifi';
      if (result.contains(ConnectivityResult.mobile)) connType = 'cellular';
      return {
        'connection_type': connType,
        'wifi_name':       wifiName,
      };
    } catch (_) {
      return {};
    }
  }
}
