import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../api_config.dart';
import '../models/team.dart';
import 'cache_service.dart' show CacheService;

class TeamService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, String>> _getHeaders(String token) async {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Token $token',
    };
  }

  static Future<List<Team>> getMyTeams(String token, {bool forceRefresh = false}) async {
    try {
      final teamsJson = await CacheService.cachedFetch<List<dynamic>>(
        key: '${CacheService.teamsKey}_my',
        cacheMinutes: 5,
        forceRefresh: forceRefresh,
        fetch: () async {
          final headers = await _getHeaders(token);
          final response = await http.get(
            Uri.parse('$_baseUrl/teams/my/'),
            headers: headers,
          ).timeout(ApiConfig.httpTimeout);

          if (response.statusCode != 200) {
            throw Exception('Server returned ${response.statusCode}');
          }
          final data = json.decode(response.body);
          return List<dynamic>.from(data['teams'] ?? const []);
        },
      );

      return teamsJson.map((team) => _parseTeam(team)).toList();
    } catch (e) {
      debugPrint('Error fetching my teams: $e');
      return [];
    }
  }

  static Team _parseTeam(Map<String, dynamic> team) {
    final maxMembers = (team['max_members'] as num?)?.toInt() ?? 10;
    final currentMembers = (team['current_members'] as num?)?.toInt() ?? 0;
    final createdAt = DateTime.tryParse(team['created_at']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(team['updated_at']?.toString() ?? '');
    return Team(
      id: team['id']?.toString() ?? '',
      name: team['name']?.toString() ?? '',
      sport: team['sport']?.toString() ?? '',
      description: team['description']?.toString() ?? '',
      type: team['type']?.toString() ?? '',
      status: team['status']?.toString() ?? 'Active',
      maxMembers: maxMembers,
      currentMembers: currentMembers,
      ownerId: team['owner_id']?.toString() ?? '',
      ownerName: team['owner_name']?.toString() ?? '',
      location: team['location']?.toString() ?? '',
      spotsLeft: (team['spots_left'] as num?)?.toInt() ??
          (maxMembers - currentMembers).clamp(0, maxMembers),
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static Future<Map<String, dynamic>> createTeam({
    required String token,
    required String name,
    required String sport,
    String description = '',
    String location = '',
    int maxMembers = 10,
    bool isSeekingPlayers = false,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/teams/create/'),
        headers: headers,
        body: json.encode({
          'name': name,
          'sport': sport,
          'description': description,
          'location': location,
          'max_members': maxMembers,
          'is_seeking_players': isSeekingPlayers,
        }),
      ).timeout(ApiConfig.httpTimeout);

      final data = json.decode(response.body);

      if (response.statusCode == 201) {
        CacheService.invalidateTeams();
        return {'success': true, 'team': data['team']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to create team'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getTeamMembersApi({
    required String token,
    required int teamId,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.get(
        Uri.parse('$_baseUrl/teams/$teamId/members/'),
        headers: headers,
      ).timeout(ApiConfig.httpTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {'success': true, 'members': data['members'] ?? []};
      } else {
        final data = json.decode(response.body);
        return {'success': false, 'error': data['error'] ?? 'Failed to get members'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getJoinRequests({
    required String token,
    required int teamId,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.get(
        Uri.parse('$_baseUrl/teams/$teamId/requests/'),
        headers: headers,
      ).timeout(ApiConfig.httpTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {'success': true, 'requests': data['requests'] ?? []};
      } else {
        final data = json.decode(response.body);
        return {'success': false, 'error': data['error'] ?? 'Failed to get requests'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }
}
