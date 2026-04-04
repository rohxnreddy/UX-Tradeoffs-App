// lib/src/services/history_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../runner/test_model.dart';

class HistoryService {
  HistoryService._();
  static final instance = HistoryService._();

  static const _key = 'test_run_history';
  static const _limit = 50;

  Future<void> saveRun(List<TestResult> results) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList(_key) ?? [];

    final run = TestRun(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      results: results,
    );

    // Insert at front
    historyJson.insert(0, jsonEncode(run.toJson()));

    // Limit size
    if (historyJson.length > _limit) {
      historyJson.removeRange(_limit, historyJson.length);
    }

    await prefs.setStringList(_key, historyJson);
  }

  Future<List<TestRun>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList(_key) ?? [];

    return historyJson
        .map((s) => TestRun.fromJson(jsonDecode(s)))
        .toList();
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
