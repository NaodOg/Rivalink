import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_config.dart';

class PaymentService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, dynamic>> initializePremium({
    required String token,
    String? returnUrl,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (returnUrl != null) body['return_url'] = returnUrl;

      final response = await http.post(
        Uri.parse('$_baseUrl/payments/initialize/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $token',
        },
        body: json.encode(body),
      ).timeout(ApiConfig.httpTimeout);

      final data = json.decode(response.body);
      return data;
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: ${e.toString()}',
      };
    }
  }

  static Future<Map<String, dynamic>> getPaymentStatus(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/payments/status/'),
        headers: {
          'Authorization': 'Token $token',
        },
      ).timeout(ApiConfig.httpTimeout);

      return json.decode(response.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: ${e.toString()}',
      };
    }
  }

  static Future<Map<String, dynamic>> getPaymentHistory(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/payments/history/'),
        headers: {
          'Authorization': 'Token $token',
        },
      ).timeout(ApiConfig.httpTimeout);

      return json.decode(response.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: ${e.toString()}',
      };
    }
  }
}
