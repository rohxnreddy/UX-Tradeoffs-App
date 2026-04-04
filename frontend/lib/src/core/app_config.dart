// lib/src/core/app_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  AppConfig._();

  /// Base URL loaded from .env — not user-editable at runtime.
  static String get apiBaseUrl => dotenv.env['API_BASE_URL'] ?? 'http://172.20.10.3:8000';
}
