// lib/src/core/app_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  AppConfig._();
  static String get apiBaseUrl => dotenv.env['API_BASE_URL'] ?? 'http://responsible-tech.bits-hyderabad.ac.in/phonebenchmarking';
}
