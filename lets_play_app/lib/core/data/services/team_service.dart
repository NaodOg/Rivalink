import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/team.dart';
import '../models/team_member.dart';
import '../models/team_invitation.dart';
import '../models/team_activity.dart';
import 'cache_service.dart' show CacheService;

class TeamService {
  static String get _baseUrl {
    if (Platform.isAndroid) {
      return 'https://unpossessively-pseudonational-shawnta.ngrok-free.dev/api';
    }
    return 'https://unpossessively-pseudonational-shawnta.ngrok-free.dev/api';
  }

  static Future<Map<String, String>> _getHeaders(String token) async {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Token $token',
    };
  }

  static Future<List<Team>> getMyTeams(String token, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await CacheService.getCachedData('${CacheService.teamsKey}_my');
      if (cached != null) {
        final List<dynamic> cachedList = cached as List<dynamic>;
        return cachedList.map((team) => _parseTeam(team)).toList();
      }
    }

    try {
      final headers = await _getHeaders(token);
      final response = await http.get(
        Uri.parse('$_baseUrl/teams/my/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> teamsJson = data['teams'] ?? [];
        
        await CacheService.setCachedData('${CacheService.teamsKey}_my', teamsJson, cacheMinutes: 5);
        
        return teamsJson.map((team) => _parseTeam(team)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching my teams: $e');
      final cached = await CacheService.getCachedData('${CacheService.teamsKey}_my');
      if (cached != null) {
        final List<dynamic> cachedList = cached as List<dynamic>;
        return cachedList.map((team) => _parseTeam(team)).toList();
      }
      return [];
    }
  }

  static Future<List<Team>> getTeamsSeekingPlayers(String token, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await CacheService.getCachedData('${CacheService.teamsKey}_seeking');
      if (cached != null) {
        final List<dynamic> cachedList = cached as List<dynamic>;
        return cachedList.map((team) => _parseTeam(team, isSeeking: true)).toList();
      }
    }

    try {
      final headers = await _getHeaders(token);
      final response = await http.get(
        Uri.parse('$_baseUrl/teams/seeking/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> teamsJson = data['teams'] ?? [];
        
        await CacheService.setCachedData('${CacheService.teamsKey}_seeking', teamsJson, cacheMinutes: 5);
        
        return teamsJson.map((team) => _parseTeam(team, isSeeking: true)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching teams seeking players: $e');
      final cached = await CacheService.getCachedData('${CacheService.teamsKey}_seeking');
      if (cached != null) {
        final List<dynamic> cachedList = cached as List<dynamic>;
        return cachedList.map((team) => _parseTeam(team, isSeeking: true)).toList();
      }
      return [];
    }
  }

  static Team _parseTeam(Map<String, dynamic> team, {bool isSeeking = false}) {
    return Team(
      id: team['id'].toString(),
      name: team['name'] ?? '',
      sport: team['sport'] ?? '',
      type: team['type'] ?? '',
      status: isSeeking ? 'Recruiting' : (team['status'] ?? 'Active'),
      maxMembers: team['max_members'] ?? 10,
      currentMembers: team['current_members'] ?? 0,
      ownerId: team['owner_id']?.toString() ?? '',
      ownerName: 'Owner',
      location: team['location'] ?? '',
      spotsLeft: team['spots_left'] ?? (team['max_members'] != null && team['current_members'] != null 
          ? team['max_members'] - team['current_members'] 
          : 0),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
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
      );

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

  static Future<Map<String, dynamic>> joinTeam({
    required String token,
    required int teamId,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/teams/join/'),
        headers: headers,
        body: json.encode({'team_id': teamId}),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        CacheService.invalidateTeams();
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to join team'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  // Keep these for backwards compatibility with dummy data
  static List<TeamMember> getTeamMembers(String teamId) {
    return [
      TeamMember(
        id: 'm1',
        userId: 'u1',
        userName: 'John Doe',
        teamId: teamId,
        role: 'Owner',
        joinedAt: DateTime.now().subtract(Duration(days: 30)),
      ),
    ];
  }

  static List<TeamInvitation> getPendingInvitationsForUser(String userId) {
    return [];
  }

  static List<TeamActivity> getUpcomingActivities(String teamId) {
    return [];
  }

  static Future<Map<String, dynamic>> leaveTeamApi({
    required String token,
    required int teamId,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/teams/leave/'),
        headers: headers,
        body: json.encode({'team_id': teamId}),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        CacheService.invalidateTeams();
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to leave team'};
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
      );

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

  static Future<Map<String, dynamic>> removeMember({
    required String token,
    required int teamId,
    required int memberId,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/teams/remove-member/'),
        headers: headers,
        body: json.encode({'team_id': teamId, 'member_id': memberId}),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to remove member'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> updateMemberRole({
    required String token,
    required int teamId,
    required int memberId,
    required String role,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/teams/update-role/'),
        headers: headers,
        body: json.encode({'team_id': teamId, 'member_id': memberId, 'role': role}),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to update role'};
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
      );

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

  static Future<Map<String, dynamic>> handleJoinRequest({
    required String token,
    required int teamId,
    required int requestId,
    required String action,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/teams/handle-request/'),
        headers: headers,
        body: json.encode({'team_id': teamId, 'request_id': requestId, 'action': action}),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to handle request'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<bool> leaveTeam(String teamId, String userId) async {
    return true;
  }

  static Future<bool> inviteMember(String teamId, String memberId) async {
    return true;
  }

  static Future<bool> acceptInvitation(String invitationId) async {
    return true;
  }

  static Future<bool> declineInvitation(String invitationId) async {
    return true;
  }

  static Future<Map<String, dynamic>> requestToJoinTeam({
    required String token,
    required int teamId,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/teams/request-join/'),
        headers: headers,
        body: json.encode({'team_id': teamId}),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to send request'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }
}
