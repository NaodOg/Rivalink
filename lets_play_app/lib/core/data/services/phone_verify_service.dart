import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_config.dart';
import 'auth_service.dart';

class PhoneVerifyService {
  PhoneVerifyService._();

  static Map<String, String>? _h(String? token) => token == null
      ? null
      : {'Content-Type': 'application/json', 'Authorization': 'Token $token'};

  /// Returns {sent: bool, dev_code: String?}.
  static Future<Map<String, dynamic>> sendCode(String token, {String? phone}) async {
    try {
      final r = await http
          .post(Uri.parse('${ApiConfig.baseUrl}/auth/phone/send-code/'),
              headers: _h(token),
              body: json.encode(phone == null ? {} : {'phone': phone}))
          .timeout(ApiConfig.httpTimeout);
      final data = json.decode(r.body);
      if (r.statusCode == 200) return data;
      return {'error': data['error'] ?? 'Failed'};
    } catch (e) {
      return {'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> verify(String token, String code) async {
    try {
      final r = await http
          .post(Uri.parse('${ApiConfig.baseUrl}/auth/phone/verify/'),
              headers: _h(token), body: json.encode({'code': code}))
          .timeout(ApiConfig.httpTimeout);
      final data = json.decode(r.body);
      if (r.statusCode == 200) return {'success': true, 'message': data['message']};
      return {'success': false, 'error': data['error'] ?? 'Failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> status(String token) async {
    try {
      final r = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/auth/phone/status/'), headers: _h(token))
          .timeout(ApiConfig.httpTimeout);
      if (r.statusCode == 200) return json.decode(r.body);
    } catch (_) {}
    return {'phone': '', 'phone_verified': false};
  }
}
