import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_config.dart';
import 'cache_service.dart';

class UserStatsService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, String>> _getHeaders(String token) async {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Token $token',
    };
  }

  static Future<Map<String, dynamic>> getUserStats(String token, int userId, {bool forceRefresh = false}) async {
    final cacheKey = 'cache_user_stats_$userId';
    try {
      final data = await CacheService.cachedFetch<Map<String, dynamic>>(
        key: cacheKey,
        cacheMinutes: 5,
        forceRefresh: forceRefresh,
        fetch: () async {
          final headers = await _getHeaders(token);
          final response = await http.get(
            Uri.parse('$_baseUrl/users/$userId/stats/'),
            headers: headers,
          ).timeout(ApiConfig.httpTimeout);

          if (response.statusCode != 200) {
            throw Exception('Server returned ${response.statusCode}');
          }
          return Map<String, dynamic>.from(json.decode(response.body));
        },
      );

      return {
        'success': true,
        'user': data['user'],
        'stats': data['stats'],
      };
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  /// Last 5 match outcomes (W/L/D), most recent first.
  static Future<List<String>> getUserForm(String token, int userId) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http
          .get(Uri.parse('$_baseUrl/users/$userId/form/'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return List<String>.from(json.decode(response.body)['form'] ?? const []);
      }
    } catch (_) {}
    return [];
  }
}
