import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    googleDisplayName = prefs.getString('googleDisplayName');
    googleEmail = prefs.getString('googleEmail');
    googlePhotoUrl = prefs.getString('googlePhotoUrl');

    deviceUsage = prefs.getString('deviceUsage');
    networkEnv = prefs.getString('networkEnv');
    testingPurpose = prefs.getString('testingPurpose');
    usageFrequency = prefs.getString('usageFrequency');

    sessionId = prefs.getString('sessionId');
    notifyListeners();
  }

  // ── Stage 1 : Google Sign-In ──────────────────────────────────────────────

  /// Maps to DB column: tester_name
  String? googleDisplayName;

  /// Maps to DB column: tester_email
  String? googleEmail;

  /// Maps to DB column: tester_photo_url
  String? googlePhotoUrl;

  Future<void> setAuth({
    required String name,
    required String email,
    String? photoUrl,
  }) async {
    googleDisplayName = name;
    googleEmail       = email;
    googlePhotoUrl    = photoUrl;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('googleDisplayName', name);
    await prefs.setString('googleEmail', email);
    if (photoUrl != null) {
      await prefs.setString('googlePhotoUrl', photoUrl);
    } else {
      await prefs.remove('googlePhotoUrl');
    }
    
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

  Future<void> setAnswers({
    required String usage,
    required String network,
    required String purpose,
    required String frequency,
  }) async {
    deviceUsage    = usage;
    networkEnv     = network;
    testingPurpose = purpose;
    usageFrequency = frequency;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('deviceUsage', usage);
    await prefs.setString('networkEnv', network);
    await prefs.setString('testingPurpose', purpose);
    await prefs.setString('usageFrequency', frequency);
    
    notifyListeners();
  }

  // ── Stage 3 : Backend session ID ─────────────────────────────────────────

  /// UUID returned by POST /device/metadata.
  /// Attached as the X-Session-Id header on every subsequent test call.
  String? sessionId;

  Future<void> setSessionId(String id) async {
    sessionId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sessionId', id);
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

  Future<void> clear() async {
    googleDisplayName = googleEmail = googlePhotoUrl = null;
    deviceUsage = networkEnv = testingPurpose = usageFrequency = null;
    sessionId   = null;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    
    try {
      await GoogleSignIn().signOut();
      await GoogleSignIn().disconnect();
    } catch (_) {}
    
    notifyListeners();
  }
}