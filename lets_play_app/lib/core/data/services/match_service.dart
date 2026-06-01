import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/match.dart';
import 'cache_service.dart' show CacheService;

class MatchService {
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

  static Future<List<PlayFairMatch>> getMatches(String token, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await CacheService.getCachedData(CacheService.matchesKey);
      if (cached != null) {
        final List<dynamic> cachedList = cached as List<dynamic>;
        return cachedList.map((match) => PlayFairMatch.fromJson(match)).toList();
      }
    }

    try {
      final headers = await _getHeaders(token);
      final response = await http.get(
        Uri.parse('$_baseUrl/matches/'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> matchesJson = data['matches'] ?? [];
        
        await CacheService.setCachedData(CacheService.matchesKey, matchesJson, cacheMinutes: 3);
        
        return matchesJson.map((match) => PlayFairMatch.fromJson(match)).toList();
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching matches: $e');
      final cached = await CacheService.getCachedData(CacheService.matchesKey);
      if (cached != null) {
        final List<dynamic> cachedList = cached as List<dynamic>;
        return cachedList.map((match) => PlayFairMatch.fromJson(match)).toList();
      }
      throw e;
    }
  }

  static Future<List<PlayFairMatch>> getMyMatches(
    String token, {
    String role = 'all',
    String status = 'all',
  }) async {
    try {
      final headers = await _getHeaders(token);
      final uri = Uri.parse('$_baseUrl/matches/my/').replace(queryParameters: {
        'role': role,
        'status': status,
      });
      final response = await http.get(
        uri,
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> matchesJson = data['matches'] ?? [];
        
        return matchesJson.map((match) => PlayFairMatch.fromJson(match)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching my matches: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> createMatch({
    required String token,
    required String title,
    required String sport,
    String description = '',
    required String location,
    required DateTime dateTime,
    int maxPlayers = 10,
    double price = 0,
    int? teamId,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/matches/create/'),
        headers: headers,
        body: json.encode({
          'title': title,
          'sport': sport,
          'description': description,
          'location': location,
          'date_time': dateTime.toUtc().toIso8601String(),
          'max_players': maxPlayers,
          'price': price,
          'team_id': teamId,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 201) {
        CacheService.invalidateMatches();
        CacheService.invalidateRecommendations();
        return {'success': true, 'match': data['match']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to create match'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getMatchDetails({
    required String token,
    required int matchId,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.get(
        Uri.parse('$_baseUrl/matches/$matchId/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {'success': true, 'match': data['match'], 'participants': data['participants']};
      } else {
        final data = json.decode(response.body);
        return {'success': false, 'error': data['error'] ?? 'Failed to load match details'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> joinMatch({
    required String token,
    required int matchId,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/matches/join/'),
        headers: headers,
        body: json.encode({'match_id': matchId}),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        CacheService.invalidateMatches();
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to join match'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> leaveMatch({
    required String token,
    required int matchId,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/matches/leave/'),
        headers: headers,
        body: json.encode({'match_id': matchId}),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        CacheService.invalidateMatches();
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to leave match'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> cancelMatch({
    required String token,
    required int matchId,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/matches/cancel/'),
        headers: headers,
        body: json.encode({'match_id': matchId}),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to cancel match'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<List<PlayFairMatch>> getMatchHistory(String token) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.get(
        Uri.parse('$_baseUrl/matches/history/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> matchesJson = data['matches'] ?? [];
        return matchesJson.map((match) => PlayFairMatch.fromJson(match)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching match history: $e');
      return [];
    }
  }

  static Future<List<PlayFairMatch>> searchMatches({
    required String token,
    String? sport,
    String? location,
    String? query,
    double? minPrice,
    double? maxPrice,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final params = <String, String>{};
      if (sport != null && sport.isNotEmpty) params['sport'] = sport;
      if (location != null && location.isNotEmpty) params['location'] = location;
      if (query != null && query.isNotEmpty) params['q'] = query;
      if (minPrice != null) params['min_price'] = minPrice.toString();
      if (maxPrice != null) params['max_price'] = maxPrice.toString();

      final uri = Uri.parse('$_baseUrl/matches/search/').replace(queryParameters: params);
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> matchesJson = data['matches'] ?? [];
        return matchesJson.map((match) => PlayFairMatch.fromJson(match)).toList();
      }
      return [];
    } catch (e) {
      print('Error searching matches: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> submitMatchResult({
    required String token,
    required int matchId,
    required String matchType,
    required String resultType,
    int? winnerTeamId,
    int? winnerUserId,
    String? winningGroup,
    int? mvpUserId,
    String score = '',
    String notes = '',
    Map<String, List<int>>? teamGroups,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final body = <String, dynamic>{
        'match_type': matchType,
        'result_type': resultType,
        'score': score,
        'notes': notes,
      };
      if (winnerTeamId != null) body['winner_team_id'] = winnerTeamId;
      if (winnerUserId != null) body['winner_user_id'] = winnerUserId;
      if (winningGroup != null && winningGroup.isNotEmpty) body['winning_group'] = winningGroup;
      if (mvpUserId != null) body['mvp_user_id'] = mvpUserId;
      if (teamGroups != null) body['team_groups'] = teamGroups;

      final response = await http.post(
        Uri.parse('$_baseUrl/matches/$matchId/result/'),
        headers: headers,
        body: json.encode(body),
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'message': data['message'], 'result': data['result']};
      }
      return {'success': false, 'error': data['error'] ?? 'Failed to submit result'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> updateMatch({
    required String token,
    required int matchId,
    String? title,
    String? description,
    String? location,
    DateTime? dateTime,
    int? maxPlayers,
    double? price,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final body = <String, dynamic>{};
      if (title != null) body['title'] = title;
      if (description != null) body['description'] = description;
      if (location != null) body['location'] = location;
      if (dateTime != null) body['date_time'] = dateTime.toUtc().toIso8601String();
      if (maxPlayers != null) body['max_players'] = maxPlayers;
      if (price != null) body['price'] = price;

      final response = await http.patch(
        Uri.parse('$_baseUrl/matches/$matchId/edit/'),
        headers: headers,
        body: json.encode(body),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'], 'match': data['match']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to update match'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }
}
