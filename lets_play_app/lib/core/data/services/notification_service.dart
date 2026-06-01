import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static String get _baseUrl {
    if (Platform.isAndroid) {
      return 'https://unpossessively-pseudonational-shawnta.ngrok-free.dev/api';
    }
    return 'https://unpossessively-pseudonational-shawnta.ngrok-free.dev/api';
  }

  static Future<Map<String, String>> _getHeaders(String token) async {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Token $token',
    };
  }

  static Future<Map<String, dynamic>> getNotifications(String token) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.get(
        Uri.parse('$_baseUrl/notifications/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'notifications': data['notifications'] ?? [],
          'unread_count': data['unread_count'] ?? 0,
        };
      }
      return {'success': false, 'notifications': [], 'unread_count': 0};
    } catch (e) {
      print('Error fetching notifications: $e');
      return {'success': false, 'notifications': [], 'unread_count': 0};
    }
  }

  static Future<Map<String, dynamic>> markAsRead({
    required String token,
    List<int>? notificationIds,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final body = <String, dynamic>{};
      if (notificationIds != null && notificationIds.isNotEmpty) {
        body['notification_ids'] = notificationIds;
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/notifications/read/'),
        headers: headers,
        body: json.encode(body),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to mark as read'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>?> getStoredSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionJson = prefs.getString('session');
      if (sessionJson != null) {
        return json.decode(sessionJson);
      }
    } catch (e) {
      print('Error loading session: $e');
    }
    return null;
  }
}
