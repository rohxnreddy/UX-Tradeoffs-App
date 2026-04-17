// lib/src/core/app_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  AppConfig._();
  static String get apiBaseUrl {
    String url = dotenv.env['API_BASE_URL'] ?? 'http://responsible-tech.bits-hyderabad.ac.in/phonebenchmarking';
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }
  static String get iqaApiBaseUrl {
    String url = dotenv.env['IQA_API_BASE_URL'] ?? apiBaseUrl;
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }
  
  /// Feature flag for image compression before sending to IQA API.
  static bool get enableIqaImageCompression => false;
}
