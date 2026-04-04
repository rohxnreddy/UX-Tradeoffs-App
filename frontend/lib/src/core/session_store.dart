// lib/src/core/session_store.dart
import 'package:flutter/foundation.dart';

/// Lightweight singleton that survives the widget tree lifecycle.
///
/// Populated in two stages:
///   1. [setAuth]      — after Google Sign-In succeeds
///   2. [setAnswers]   — after the questionnaire completes
///
/// After both stages, [MetadataService.collectAndSend] fires and stores
/// the returned backend [sessionId] via [setSessionId].
class SessionStore extends ChangeNotifier {
  SessionStore._();
  static final SessionStore instance = SessionStore._();

  // ── Stage 1 : Google Sign-In ──────────────────────────────────────────────

  /// Maps to DB column: tester_name
  String? googleDisplayName;

  /// Maps to DB column: tester_email
  String? googleEmail;

  /// Maps to DB column: tester_photo_url
  String? googlePhotoUrl;

  void setAuth({
    required String name,
    required String email,
    String? photoUrl,
  }) {
    googleDisplayName = name;
    googleEmail       = email;
    googlePhotoUrl    = photoUrl;
    notifyListeners();
  }

  // ── Stage 2 : Questionnaire ───────────────────────────────────────────────

  /// Maps to DB column: device_usage
  String? deviceUsage;

  /// Maps to DB column: network_env
  String? networkEnv;

  /// Maps to DB column: testing_purpose
  String? testingPurpose;

  /// Maps to DB column: usage_frequency
  String? usageFrequency;

  void setAnswers({
    required String usage,
    required String network,
    required String purpose,
    required String frequency,
  }) {
    deviceUsage    = usage;
    networkEnv     = network;
    testingPurpose = purpose;
    usageFrequency = frequency;
    notifyListeners();
  }

  // ── Stage 3 : Backend session ID ─────────────────────────────────────────

  /// UUID returned by POST /device/metadata.
  /// Attached as the X-Session-Id header on every subsequent test call.
  String? sessionId;

  void setSessionId(String id) {
    sessionId = id;
    notifyListeners();
  }

  // ── Computed state ────────────────────────────────────────────────────────

  bool get isLoggedIn  => googleEmail != null;
  bool get hasAnswered => deviceUsage != null && networkEnv != null &&
      testingPurpose != null && usageFrequency != null;
  bool get hasSession  => sessionId != null;

  /// True once sign-in AND all four questionnaire answers are present.
  bool get isReady => isLoggedIn && hasAnswered;

  // ── Reset ─────────────────────────────────────────────────────────────────

  void clear() {
    googleDisplayName = googleEmail = googlePhotoUrl = null;
    deviceUsage = networkEnv = testingPurpose = usageFrequency = null;
    sessionId   = null;
    notifyListeners();
  }
}