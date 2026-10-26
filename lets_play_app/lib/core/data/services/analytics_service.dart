import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api_config.dart';
import 'auth_service.dart';

/// Lightweight product-analytics client.
///
/// - Batches events (10 per batch / every 15s) and never blocks the UI.
/// - Queues failed batches in SharedPreferences and retries on the next flush.
/// - Anonymous until sign-in; `identify()` switches to the user's account.
/// - Can be disabled from Settings (privacy).
class AnalyticsService {
  AnalyticsService._();

  static const _prefsQueue = 'analytics_queue';
  static const _prefsAnon = 'analytics_anon_id';
  static const _prefsEnabled = 'analytics_enabled';
  static const _sessionIdle = Duration(minutes: 30);
  static const _batchSize = 10;

  static String _anonId = '';
  static String? _userId;
  static String _sessionId = '';
  static DateTime _lastActivity = DateTime.now();
  static final List<Map<String, dynamic>> _queue = [];
  static Timer? _timer;
  static bool _enabled = true;
  static bool _initialized = false;

  static bool get enabled => _enabled;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefsEnabled) ?? true;
      _anonId = prefs.getString(_prefsAnon) ?? '';
      if (_anonId.isEmpty) {
        _anonId = 'anon-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 30)}';
        await prefs.setString(_prefsAnon, _anonId);
      }
      final saved = prefs.getStringList(_prefsQueue) ?? const [];
      for (final raw in saved.take(50)) {
        try {
          _queue.add(json.decode(raw) as Map<String, dynamic>);
        } catch (_) {}
      }
    } catch (_) {}

    _rotateSession();
    _timer ??= Timer.periodic(const Duration(seconds: 15), (_) => flush());
    screen('App');
  }

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (!value) {
      _queue.clear();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefsQueue);
      } catch (_) {}
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsEnabled, value);
    } catch (_) {}
  }

  static void identify(int? userId) {
    _userId = userId?.toString();
    event('identify', {'user_id': _userId});
  }

  static void screen(String name) {
    event('screen_viewed', {'screen': name});
  }

  static void screenExit(String name, int durationMs) {
    if (durationMs < 250) return;
    event('screen_exited', {'screen': name, 'duration_ms': durationMs});
  }

  static void event(String name, [Map<String, dynamic>? properties]) {
    if (!_enabled) return;

    final now = DateTime.now();
    if (now.difference(_lastActivity) > _sessionIdle) _rotateSession();
    _lastActivity = now;

    _queue.add({
      'name': name,
      'properties': properties ?? const <String, dynamic>{},
      'ts': now.millisecondsSinceEpoch,
    });
    if (_queue.length >= _batchSize) flush();
  }

  static Future<void> flush() async {
    if (!_enabled || _queue.isEmpty) return;
    final batch = _queue.take(_batchSize).toList();
    _queue.removeRange(0, batch.length);

    final body = {
      'session_id': _sessionId,
      'anon_id': _anonId,
      'platform': defaultTargetPlatform.name.toLowerCase(),
      'app_version': '1.0.0',
      'user_id': _userId,
      'events': batch,
    };

    String? token;
    try {
      final session = await AuthService.getSession();
      token = session?['token'] as String?;
    } catch (_) {}

    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/analytics/events/'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Token $token',
            },
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 201) {
        _requeue(batch);
      } else {
        _persistQueue();
      }
    } catch (_) {
      _requeue(batch);
    }
  }

  static void _requeue(List<Map<String, dynamic>> batch) {
    _queue.insertAll(0, batch);
    if (_queue.length > 200) {
      _queue.removeRange(0, _queue.length - 200);
    }
    _persistQueue();
  }

  static Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _prefsQueue,
        _queue.map((e) => json.encode(e)).toList(),
      );
    } catch (_) {}
  }

  static void _rotateSession() {
    _sessionId =
        's-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${Random().nextInt(1 << 20)}';
  }
}
