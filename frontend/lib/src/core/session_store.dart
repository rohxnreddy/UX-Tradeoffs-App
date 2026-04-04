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

    ageGroup = prefs.getString('ageGroup');
    phoneCondition = prefs.getString('phoneCondition');
    phoneDuration = prefs.getString('phoneDuration');
    phoneHistory = prefs.getString('phoneHistory');
    primaryUsage = prefs.getString('primaryUsage');
    internetFrequency = prefs.getString('internetFrequency');
    phoneSharing = prefs.getString('phoneSharing');
    internetConnectionType = prefs.getString('internetConnectionType');
    phoneAcquisition = prefs.getString('phoneAcquisition');

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

  String? ageGroup;
  String? phoneCondition;
  String? phoneDuration;
  String? phoneHistory;
  String? primaryUsage;
  String? internetFrequency;
  String? phoneSharing;
  String? internetConnectionType;
  String? phoneAcquisition;

  Future<void> setAnswers({
    required String pAgeGroup,
    required String pPhoneCondition,
    required String pPhoneDuration,
    required String pPhoneHistory,
    required String pPrimaryUsage,
    required String pInternetFrequency,
    required String pPhoneSharing,
    required String pInternetConnectionType,
    required String pPhoneAcquisition,
  }) async {
    ageGroup = pAgeGroup;
    phoneCondition = pPhoneCondition;
    phoneDuration = pPhoneDuration;
    phoneHistory = pPhoneHistory;
    primaryUsage = pPrimaryUsage;
    internetFrequency = pInternetFrequency;
    phoneSharing = pPhoneSharing;
    internetConnectionType = pInternetConnectionType;
    phoneAcquisition = pPhoneAcquisition;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ageGroup', pAgeGroup);
    await prefs.setString('phoneCondition', pPhoneCondition);
    await prefs.setString('phoneDuration', pPhoneDuration);
    await prefs.setString('phoneHistory', pPhoneHistory);
    await prefs.setString('primaryUsage', pPrimaryUsage);
    await prefs.setString('internetFrequency', pInternetFrequency);
    await prefs.setString('phoneSharing', pPhoneSharing);
    await prefs.setString('internetConnectionType', pInternetConnectionType);
    await prefs.setString('phoneAcquisition', pPhoneAcquisition);
    
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
  bool get hasAnswered => ageGroup != null && phoneCondition != null &&
      phoneDuration != null && phoneHistory != null && primaryUsage != null &&
      internetFrequency != null && phoneSharing != null &&
      internetConnectionType != null && phoneAcquisition != null;
  bool get hasSession  => sessionId != null;

  /// True once sign-in AND all four questionnaire answers are present.
  bool get isReady => isLoggedIn && hasAnswered;

  // ── Reset ─────────────────────────────────────────────────────────────────

  Future<void> clear() async {
    googleDisplayName = googleEmail = googlePhotoUrl = null;
    ageGroup = phoneCondition = phoneDuration = phoneHistory = primaryUsage = 
        internetFrequency = phoneSharing = internetConnectionType = phoneAcquisition = null;
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