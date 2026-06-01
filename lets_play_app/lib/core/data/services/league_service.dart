import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'cache_service.dart';

class LeagueService {
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

  static Future<List<Map<String, dynamic>>> getLeagues(String token, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await CacheService.getCachedData('${CacheService.leaguesKey}_all');
      if (cached != null) {
        return List<Map<String, dynamic>>.from(cached as List);
      }
    }

    try {
      final headers = await _getHeaders(token);
      final response = await http.get(
        Uri.parse('$_baseUrl/leagues/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final leagues = List<Map<String, dynamic>>.from(data['leagues'] ?? []);
        
        await CacheService.setCachedData('${CacheService.leaguesKey}_all', leagues, cacheMinutes: 5);
        
        return leagues;
      }
      return [];
    } catch (e) {
      print('Error fetching leagues: $e');
      final cached = await CacheService.getCachedData('${CacheService.leaguesKey}_all');
      if (cached != null) {
        return List<Map<String, dynamic>>.from(cached as List);
      }
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getMyLeagues(String token) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.get(
        Uri.parse('$_baseUrl/leagues/my/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['leagues'] ?? []);
      }
      return [];
    } catch (e) {
      print('Error fetching my leagues: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> getLeagueDetails(String token, int leagueId) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.get(
        Uri.parse('$_baseUrl/leagues/$leagueId/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {'success': true, 'league': data['league'], 'standings': data['standings']};
      }
      return {'success': false, 'error': 'Failed to load league details'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> createLeague({
    required String token,
    required String name,
    required String sport,
    String format = '5v5',
    int maxTeams = 8,
    double entryFee = 0,
    String prize = '',
    String location = '',
    required DateTime startDate,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/leagues/create/'),
        headers: headers,
        body: json.encode({
          'name': name,
          'sport': sport,
          'format': format,
          'max_teams': maxTeams,
          'entry_fee': entryFee,
          'prize': prize,
          'location': location,
          'start_date': startDate.toUtc().toIso8601String(),
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 201) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to create league'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> joinLeague({
    required String token,
    required int leagueId,
    required int teamId,
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.post(
        Uri.parse('$_baseUrl/leagues/join/'),
        headers: headers,
        body: json.encode({
          'league_id': leagueId,
          'team_id': teamId,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to join league'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }
}
