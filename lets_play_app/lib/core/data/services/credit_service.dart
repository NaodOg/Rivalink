import 'dart:convert';
import 'package:http/http.dart' as http;

import '../api_config.dart';

class CreditService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, dynamic>> getCredits(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/credits/'),
        headers: {'Authorization': 'Token $token'},
      ).timeout(ApiConfig.httpTimeout);
      final data = json.decode(response.body);
      if (response.statusCode == 200) return data as Map<String, dynamic>;
      return {'success': false, 'message': data['message'] ?? 'Could not load credit'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }
}
