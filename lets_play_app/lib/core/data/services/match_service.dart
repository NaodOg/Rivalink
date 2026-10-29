import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../api_config.dart';
import '../models/match.dart';
import 'cache_service.dart' show CacheService;

class MatchService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, String>> _getHeaders(String token) async {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Token $token',
    };
  }

  static Future<List<RivalinkMatch>> getMatches(String token, {bool forceRefresh = false}) async {
    final matchesJson = await CacheService.cachedFetch<List<dynamic>>(
      key: CacheService.matchesKey,
      cacheMinutes: 3,
      forceRefresh: forceRefresh,
      fetch: () async {
        final headers = await _getHeaders(token);
        final response = await http.get(
          Uri.parse('$_baseUrl/matches/'),
          headers: headers,
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) {
          throw Exception('Server returned ${response.statusCode}');
        }
        final data = json.decode(response.body);
        return List<dynamic>.from(data['matches'] ?? const []);
      },
    );

    return matchesJson.map((match) => RivalinkMatch.fromJson(match)).toList();
  }

  static Future<List<RivalinkMatch>> getMyMatches(
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
      ).timeout(ApiConfig.httpTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> matchesJson = data['matches'] ?? [];
        
        return matchesJson.map((match) => RivalinkMatch.fromJson(match)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching my matches: $e');
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
    String skillLevel = 'any',
    int? teamId,
    int? venueId,
    int? minPlayers,
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
          'skill_level': skillLevel,
          'team_id': teamId,
          'venue_id': venueId,
          'min_players': minPlayers ?? 0,
        }),
      ).timeout(ApiConfig.httpTimeout);

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

  static Future<List<dynamic>> getRecommendations(String token, {bool forceRefresh = false}) async {
    try {
      return await CacheService.cachedFetch<List<dynamic>>(
        key: CacheService.recommendationsKey,
        cacheMinutes: 3,
        forceRefresh: forceRefresh,
        fetch: () async {
          final headers = await _getHeaders(token);
          final response = await http
              .get(Uri.parse('$_baseUrl/matches/recommendations/'), headers: headers)
              .timeout(const Duration(seconds: 10));
          if (response.statusCode != 200) {
            throw Exception('Server returned ${response.statusCode}');
          }
          final data = json.decode(response.body);
          return List<dynamic>.from(data['recommendations'] ?? const []);
        },
      );
    } catch (e) {
      debugPrint('Error fetching recommendations: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> submitReport({
    required String token,
    int? targetUserId,
    int? matchId,
    required String category,
    String details = '',
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/reports/create/'),
        headers: headers,
        body: json.encode({
          'target_user_id': targetUserId,
          'match_id': matchId,
          'category': category,
          'details': details,
        }),
      ).timeout(ApiConfig.httpTimeout);
      final data = json.decode(response.body);
      if (response.statusCode == 201) {
        return {'success': true, 'message': data['message']};
      }
      return {'success': false, 'error': data['error'] ?? 'Failed to submit report'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> toggleBlock(String token, int userId) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/blocks/toggle/'),
        headers: headers,
        body: json.encode({'user_id': userId}),
      ).timeout(ApiConfig.httpTimeout);
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'blocked': data['blocked']};
      }
      return {'success': false, 'error': data['error'] ?? 'Failed'};
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
      ).timeout(ApiConfig.httpTimeout);

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
      ).timeout(ApiConfig.httpTimeout);

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        CacheService.invalidateMatches();
        CacheService.invalidateRecommendations();
        return {'success': true, ...data};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to join match'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> payMatchShare({
    required String token,
    required int matchId,
    String returnUrl = '',
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/matches/$matchId/pay/'),
        headers: headers,
        body: json.encode({'return_url': returnUrl}),
      ).timeout(ApiConfig.httpTimeout);
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        CacheService.invalidateMatches();
        return {'success': true, ...data};
      }
      return {'success': false, 'message': data['message'] ?? data['error'] ?? 'Payment failed'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> withdrawMatch({
    required String token,
    required int matchId,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/matches/$matchId/withdraw/'),
        headers: headers,
      ).timeout(ApiConfig.httpTimeout);
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        CacheService.invalidateMatches();
        CacheService.invalidateRecommendations();
        return {'success': true, ...data};
      }
      return {'success': false, 'error': data['error'] ?? 'Could not withdraw'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> requestVenueBooking({
    required String token,
    required int matchId,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/matches/$matchId/booking-request/'),
        headers: headers,
      ).timeout(ApiConfig.httpTimeout);
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        CacheService.invalidateMatches();
        return {'success': true, ...data};
      }
      return {'success': false, 'error': data['error'] ?? 'Could not request booking'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> confirmVenueBooking({
    required String token,
    required int matchId,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/matches/$matchId/booking-confirm/'),
        headers: headers,
      ).timeout(ApiConfig.httpTimeout);
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        CacheService.invalidateMatches();
        return {'success': true, ...data};
      }
      return {'success': false, 'error': data['error'] ?? 'Could not confirm booking'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
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
      ).timeout(ApiConfig.httpTimeout);

      final data = json.decode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        CacheService.invalidateMatches();
        CacheService.invalidateUserStats();
        return {'success': true, 'message': data['message'], 'result': data['result']};
      }
      return {'success': false, 'error': data['error'] ?? 'Failed to submit result'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }
}
