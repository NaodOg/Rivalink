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
    
    if (!forceRefresh) {
      final cached = await CacheService.getCachedData(cacheKey);
      if (cached != null) {
        return {
          'success': true,
          'user': cached['user'],
          'stats': cached['stats'],
        };
      }
    }

    try {
      final headers = await _getHeaders(token);
      final response = await http.get(
        Uri.parse('$_baseUrl/users/$userId/stats/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        await CacheService.setCachedData(cacheKey, data, cacheMinutes: 5);
        
        return {
          'success': true,
          'user': data['user'],
          'stats': data['stats'],
        };
      }
      return {'success': false, 'error': 'Failed to fetch user stats'};
    } catch (e) {
      final cached = await CacheService.getCachedData(cacheKey);
      if (cached != null) {
        return {
          'success': true,
          'user': cached['user'],
          'stats': cached['stats'],
        };
      }
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
