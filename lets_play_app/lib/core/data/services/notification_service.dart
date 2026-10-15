import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_config.dart';
import 'auth_service.dart';

class NotificationService {
  static String get _baseUrl => ApiConfig.baseUrl;

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
      ).timeout(ApiConfig.httpTimeout);

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
      ).timeout(ApiConfig.httpTimeout);

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to mark as read'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error'};
    }
  }

  static Future<Map<String, dynamic>?> getStoredSession() async {
    try {
      final session = await AuthService.getSession();
      return session;
    } catch (e) {
      return null;
    }
  }
}
