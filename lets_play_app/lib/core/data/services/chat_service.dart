import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../api_config.dart';

class ChatMessage {
  final int id;
  final int userId;
  final String userName;
  final String message;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.userId,
    required this.userName,
    required this.message,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? 0,
      userName: json['user_name'] ?? 'Unknown',
      message: json['message'] ?? '',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

class ChatService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, String>> _getHeaders(String token) async {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Token $token',
    };
  }

  static Future<List<ChatMessage>> getMatchChat({
    required String token,
    required int matchId,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.get(
        Uri.parse('$_baseUrl/matches/$matchId/chat/'),
        headers: headers,
      ).timeout(ApiConfig.httpTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> messagesJson = data['messages'] ?? [];
        return messagesJson.map((m) => ChatMessage.fromJson(m)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching chat: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> sendMessage({
    required String token,
    required int matchId,
    required String message,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/matches/$matchId/chat/send/'),
        headers: headers,
        body: json.encode({'message': message}),
      ).timeout(ApiConfig.httpTimeout);

      final data = json.decode(response.body);

      if (response.statusCode == 201) {
        return {'success': true, 'message': data};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to send message'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  // ── Team Chat ──

  static Future<List<ChatMessage>> getTeamChat({
    required String token,
    required int teamId,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.get(
        Uri.parse('$_baseUrl/teams/$teamId/chat/'),
        headers: headers,
      ).timeout(ApiConfig.httpTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> messagesJson = data['messages'] ?? [];
        return messagesJson.map((m) => ChatMessage.fromJson(m)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching team chat: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> sendTeamMessage({
    required String token,
    required int teamId,
    required String message,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/teams/$teamId/chat/send/'),
        headers: headers,
        body: json.encode({'message': message}),
      ).timeout(ApiConfig.httpTimeout);

      final data = json.decode(response.body);

      if (response.statusCode == 201) {
        return {'success': true, 'message': data};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to send message'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }
}
