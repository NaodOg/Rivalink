import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api_config.dart';

class SocialService {
  SocialService._();

  static Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Token $token',
      };

  static Future<Map<String, dynamic>> me(String token) async {
    try {
      final r = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/social/me/'), headers: _headers(token))
          .timeout(ApiConfig.httpTimeout);
      if (r.statusCode == 200) return json.decode(r.body);
    } catch (e) {
      debugPrint('social/me error: $e');
    }
    return {};
  }

  static Future<bool> followToggle(String token, int userId) async {
    try {
      final r = await http
          .post(Uri.parse('${ApiConfig.baseUrl}/social/follow/'),
              headers: _headers(token), body: json.encode({'user_id': userId}))
          .timeout(ApiConfig.httpTimeout);
      if (r.statusCode == 200) return json.decode(r.body)['following'] == true;
    } catch (e) {
      debugPrint('follow error: $e');
    }
    return false;
  }

  static Future<List<dynamic>> _list(String token, String path) async {
    try {
      final r = await http
          .get(Uri.parse('${ApiConfig.baseUrl}$path'), headers: _headers(token))
          .timeout(ApiConfig.httpTimeout);
      if (r.statusCode == 200) return List<dynamic>.from(json.decode(r.body)['users'] ?? []);
    } catch (e) {
      debugPrint('$path error: $e');
    }
    return [];
  }

  static Future<List<dynamic>> following(String token) => _list(token, '/social/following/');
  static Future<List<dynamic>> followers(String token) => _list(token, '/social/followers/');
  static Future<List<dynamic>> teammates(String token) => _list(token, '/social/teammates/');

  static Future<List<dynamic>> referrals(String token) async {
    try {
      final r = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/social/referrals/'), headers: _headers(token))
          .timeout(ApiConfig.httpTimeout);
      if (r.statusCode == 200) return List<dynamic>.from(json.decode(r.body)['referrals'] ?? []);
    } catch (e) {
      debugPrint('referrals error: $e');
    }
    return [];
  }
}
