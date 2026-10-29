import 'dart:convert';
import 'package:http/http.dart' as http;

import '../api_config.dart';

class HostEarningsService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, dynamic>> getEarnings(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/host/earnings/'),
        headers: {'Authorization': 'Token $token'},
      ).timeout(ApiConfig.httpTimeout);
      final data = json.decode(response.body);
      if (response.statusCode == 200) return data as Map<String, dynamic>;
      return {'success': false, 'message': data['message'] ?? 'Could not load earnings'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> requestPayout({
    required String token,
    required String amount,
    required String method,
    required String destination,
    String note = '',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/host/payouts/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $token',
        },
        body: json.encode({
          'amount': amount,
          'method': method,
          'destination': destination,
          'note': note,
        }),
      ).timeout(ApiConfig.httpTimeout);
      final data = json.decode(response.body);
      if (response.statusCode == 201) return data as Map<String, dynamic>;
      return {'success': false, 'message': data['message'] ?? 'Payout request failed'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> cancelPayout({
    required String token,
    required int payoutId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/host/payouts/$payoutId/cancel/'),
        headers: {'Authorization': 'Token $token'},
      ).timeout(ApiConfig.httpTimeout);
      final data = json.decode(response.body);
      if (response.statusCode == 200) return data as Map<String, dynamic>;
      return {'success': false, 'message': data['message'] ?? 'Could not cancel payout'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }
}
