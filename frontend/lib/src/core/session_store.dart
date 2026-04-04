// lib/src/core/session_store.dart
import 'package:flutter/foundation.dart';

/// Lightweight singleton that survives the widget tree lifecycle.
class SessionStore extends ChangeNotifier {
  SessionStore._();
  static final SessionStore instance = SessionStore._();

  // ── Auth ──────────────────────────────────────────────────────────────────
  String? googleDisplayName;
  String? googleEmail;
  String? googlePhotoUrl;

  // ── Questionnaire answers ─────────────────────────────────────────────────
  String? deviceUsage;      // Q1
  String? networkEnv;       // Q2
  String? testingPurpose;   // Q3
  String? usageFrequency;   // Q4

  // ── Backend session ───────────────────────────────────────────────────────
  String? sessionId;

  bool get isLoggedIn    => googleEmail != null;
  bool get hasAnswered   => deviceUsage != null && networkEnv != null;
  bool get hasSession    => sessionId != null;

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

  void setSessionId(String id) {
    sessionId = id;
    notifyListeners();
  }

  void clear() {
    googleDisplayName = googleEmail = googlePhotoUrl = null;
    deviceUsage = networkEnv = testingPurpose = usageFrequency = null;
    sessionId   = null;
    notifyListeners();
  }
}
