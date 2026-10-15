import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api_config.dart';
import 'upload_media_type.dart';

class AuthService {
  static String get baseUrl => ApiConfig.baseUrl;

  /// Sign up a new user
  static Future<Map<String, dynamic>> signup({
    required String name,
    required String phone,
    required String email,
    required String password,
    String location = '',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/signup/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'phone': phone,
          'email': email,
          'password': password,
          'location': location,
        }),
      ).timeout(ApiConfig.httpTimeout);

      final data = json.decode(response.body);

      if (response.statusCode == 201) {
        // Success
        return {
          'success': true,
          'message': data['message'],
          'token': data['token'],
          'user': data['user'],
        };
      } else {
        // Error
        return {
          'success': false,
          'message': data['error'] ?? 'Signup failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: ${e.toString()}',
      };
    }
  }

  /// Login an existing user
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
        }),
      ).timeout(ApiConfig.httpTimeout);

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        // Success
        return {
          'success': true,
          'message': data['message'],
          'token': data['token'],
          'user': data['user'],
        };
      } else {
        // Error
        return {
          'success': false,
          'message': data['error'] ?? 'Login failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: ${e.toString()}',
      };
    }
  }

  /// Logout user
  static Future<Map<String, dynamic>> logout(String token) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/logout/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $token',
        },
      ).timeout(ApiConfig.httpTimeout);

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data['message'],
        };
      } else {
        return {
          'success': false,
          'message': data['error'] ?? 'Logout failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: ${e.toString()}',
      };
    }
  }

  // --- Session Management ---

  static const String _keyToken = 'auth_token';
  static const String _keyUser = 'user_data';
  static final FlutterSecureStorage _storage = FlutterSecureStorage();

  /// Save session data
  static Future<void> saveSession(String token, Map<String, dynamic> userData) async {
    await _storage.write(key: _keyToken, value: token);
    await _storage.write(key: _keyUser, value: json.encode(userData));
  }

  /// Get saved session data
  static Future<Map<String, dynamic>?> getSession() async {
    final token = await _storage.read(key: _keyToken);
    final userJson = await _storage.read(key: _keyUser);

    if (token != null && userJson != null) {
      return {
        'token': token,
        'user': json.decode(userJson),
      };
    }
    return null;
  }

  /// Update user profile
  static Future<Map<String, dynamic>> updateProfile({
    required String token,
    String? name,
    String? email,
    String? profileImage,
    String? bio,
    String? location,
    List<String>? favoriteSports,
  }) async {
    try {
      final Map<String, dynamic> updateData = {};
      if (name != null) updateData['name'] = name;
      if (email != null) updateData['email'] = email;
      if (profileImage != null) updateData['profile_image'] = profileImage;
      if (bio != null) updateData['bio'] = bio;
      if (location != null) updateData['location'] = location;
      if (favoriteSports != null) updateData['favorite_sports'] = favoriteSports.join(',');

      final response = await http.patch(
        Uri.parse('$baseUrl/auth/profile/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $token',
        },
        body: json.encode(updateData),
      ).timeout(ApiConfig.httpTimeout);

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        // Update successful
        return {
          'success': true,
          'message': data['message'],
          'user': data['user'],
        };
      } else {
        // Error
        return {
          'success': false,
          'message': data['error'] ?? 'Profile update failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: ${e.toString()}',
      };
    }
  }

  /// Fetch the current user's profile
  static Future<Map<String, dynamic>?> getProfile(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/profile/'),
        headers: {'Authorization': 'Token $token'},
      ).timeout(ApiConfig.httpTimeout);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['user'] as Map<String, dynamic>?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Upload profile image
  static Future<Map<String, dynamic>> uploadProfileImage({
    required String token,
    required String imagePath,
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/auth/profile/image/'));
      request.headers['Authorization'] = 'Token $token';
      request.files.add(await http.MultipartFile.fromPath('image', imagePath, contentType: imageMediaType(imagePath)));
      final streamed = await request.send().timeout(ApiConfig.httpTimeout);
      final response = await http.Response.fromStream(streamed);
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'url': data['url']};
      }
      return {'success': false, 'message': data['error'] ?? 'Upload failed'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Clear session data
  static Future<void> clearSession() async {
    await _storage.delete(key: _keyToken);
    await _storage.delete(key: _keyUser);
  }
}
