import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api_config.dart';

/// Push notifications client.
///
/// The backend is fully ready (POST /devices/register/). To switch push on:
///   1. Create a Firebase project and run `flutterfire configure`.
///   2. `flutter pub add firebase_core firebase_messaging`
///   3. Bump the Kotlin Gradle plugin (firebase_messaging needs the newer DSL).
///   4. Point [tokenProvider] at FCM, e.g.:
///        PushService.tokenProvider = () => FirebaseMessaging.instance.getToken();
/// Until then every call here is a safe no-op.
class PushService {
  PushService._();

  /// Plug the FCM token source in here. Returns null when unavailable.
  static Future<String?> Function()? tokenProvider;

  static String? _authToken;
  static String? _deviceToken;

  static Future<void> register(String authToken) async {
    _authToken = authToken;
    final provider = tokenProvider;
    if (provider == null) return;
    try {
      final deviceToken = await provider();
      if (deviceToken == null || deviceToken.isEmpty) return;
      _deviceToken = deviceToken;
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/devices/register/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $authToken',
        },
        body: json.encode({'token': deviceToken, 'device_type': 'android'}),
      ).timeout(ApiConfig.httpTimeout);
    } catch (e) {
      debugPrint('Push register failed: $e');
    }
  }

  static Future<void> unregister() async {
    final auth = _authToken;
    final device = _deviceToken;
    _authToken = null;
    _deviceToken = null;
    if (auth == null || device == null) return;
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/devices/unregister/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $auth',
        },
        body: json.encode({'token': device}),
      ).timeout(ApiConfig.httpTimeout);
    } catch (e) {
      debugPrint('Push unregister failed: $e');
    }
  }
}
