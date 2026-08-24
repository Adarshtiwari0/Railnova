import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';

/// Talks to the backend's /api/notifications endpoints so a favorited
/// train's delay updates can be pushed to this device. Every call is
/// best-effort: if Firebase isn't configured, permission is denied, or the
/// backend/network fails, favoriting still works locally — the device just
/// won't get push alerts for that train.
class NotificationService {
  static Future<String?> _getToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      return await messaging.getToken();
    } catch (_) {
      return null;
    }
  }

  static Future<void> subscribeToTrain({
    required String trainNumber,
    required String trainName,
  }) async {
    final token = await _getToken();
    if (token == null) return;

    try {
      await http.post(
        Uri.parse("${AppConfig.baseUrl}/notifications/subscribe"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "deviceToken": token,
          "trainNumber": trainNumber,
          "trainName": trainName,
        }),
      ).timeout(AppConfig.apiTimeout);
    } catch (_) {
      // Best-effort — see class doc.
    }
  }

  static Future<void> unsubscribeFromTrain(String trainNumber) async {
    final token = await _getToken();
    if (token == null) return;

    try {
      await http.post(
        Uri.parse("${AppConfig.baseUrl}/notifications/unsubscribe"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"deviceToken": token, "trainNumber": trainNumber}),
      ).timeout(AppConfig.apiTimeout);
    } catch (_) {
      // Best-effort — see class doc.
    }
  }
}
