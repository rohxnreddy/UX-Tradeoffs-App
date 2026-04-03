import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Shared session manager for field testing.
/// Stores the current session ID and provides methods to
/// create sessions and log results.
class SessionManager extends ChangeNotifier {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  String? _sessionId;
  String? _phoneModel;
  String? _testerName;
  String _apiBaseUrl = "http://172.20.10.3:8000";

  String? get sessionId => _sessionId;
  String? get phoneModel => _phoneModel;
  String? get testerName => _testerName;
  String get apiBaseUrl => _apiBaseUrl;
  bool get hasSession => _sessionId != null;

  void setApiBaseUrl(String url) {
    _apiBaseUrl = url;
    notifyListeners();
  }

  /// Create a new session on the backend.
  Future<bool> createSession(String phoneModel, String testerName) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/device/metadata'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'device_model': phoneModel,
              'tester_name': testerName,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _sessionId = data['session_id'] as String;
        _phoneModel = phoneModel;
        _testerName = testerName;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Session creation failed: $e');
      return false;
    }
  }

  /// Clear the current session.
  void clearSession() {
    _sessionId = null;
    _phoneModel = null;
    _testerName = null;
    notifyListeners();
  }

  /// Show a dialog to set up a new session.
  static Future<bool> showSessionDialog(
    BuildContext context, {
    String? currentApiUrl,
  }) async {
    final session = SessionManager();
    final phoneController = TextEditingController(
      text: session._phoneModel ?? '',
    );
    final testerController = TextEditingController(
      text: session._testerName ?? '',
    );
    final apiController = TextEditingController(
      text: currentApiUrl ?? session._apiBaseUrl,
    );

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool isLoading = false;
        String? errorMsg;

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.phone_android, color: Colors.teal.shade700),
                  const SizedBox(width: 8),
                  const Text("New Test Session"),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (session.hasSession)
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Active: ${session._phoneModel} (${session._sessionId})",
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: phoneController,
                      decoration: InputDecoration(
                        labelText: "Phone Model *",
                        hintText: "e.g., iPhone 15 Pro, Pixel 8",
                        prefixIcon: const Icon(Icons.smartphone),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: testerController,
                      decoration: InputDecoration(
                        labelText: "Tester Name",
                        hintText: "Optional",
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: apiController,
                      decoration: InputDecoration(
                        labelText: "Server URL",
                        hintText: "http://...",
                        prefixIcon: const Icon(Icons.cloud),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    if (errorMsg != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorMsg!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (session.hasSession)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text("Keep Current"),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final phone = phoneController.text.trim();
                          if (phone.isEmpty) {
                            setDialogState(
                              () => errorMsg = "Phone model is required",
                            );
                            return;
                          }

                          setDialogState(() {
                            isLoading = true;
                            errorMsg = null;
                          });

                          session.setApiBaseUrl(apiController.text.trim());
                          final success = await session.createSession(
                            phone,
                            testerController.text.trim(),
                          );

                          if (success) {
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } else {
                            setDialogState(() {
                              isLoading = false;
                              errorMsg = "Failed to connect to server";
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text("Start Session"),
                ),
              ],
            );
          },
        );
      },
    );

    return result ?? false;
  }
}
