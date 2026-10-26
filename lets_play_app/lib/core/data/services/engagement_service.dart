import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_config.dart';

class EngagementService {
  static Future<Map<String, dynamic>> status(String token) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/engagement/status/'),
        headers: {'Authorization': 'Token $token'},
      ).timeout(ApiConfig.httpTimeout);
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {};
    } catch (_) {
      return {};
    }
  }
}
