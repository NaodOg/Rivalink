import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../api_config.dart';
import 'cache_service.dart';

class LeagueFixture {
  final int id;
  final int leagueId;
  final int roundNumber;
  final int homeTeamId;
  final String homeTeamName;
  final int awayTeamId;
  final String awayTeamName;
  final String? kickoff;
  final int? matchId;
  final int? homeScore;
  final int? awayScore;
  final bool isWalkover;
  final String status;

  LeagueFixture({
    required this.id,
    required this.leagueId,
    required this.roundNumber,
    required this.homeTeamId,
    required this.homeTeamName,
    required this.awayTeamId,
    required this.awayTeamName,
    this.kickoff,
    this.matchId,
    this.homeScore,
    this.awayScore,
    this.isWalkover = false,
    required this.status,
  });

  factory LeagueFixture.fromJson(Map<String, dynamic> json) {
    return LeagueFixture(
      id: json['id'] ?? 0,
      leagueId: json['league_id'] ?? 0,
      roundNumber: json['round_number'] ?? 1,
      homeTeamId: json['home_team_id'] ?? 0,
      homeTeamName: json['home_team_name'] ?? 'TBD',
      awayTeamId: json['away_team_id'] ?? 0,
      awayTeamName: json['away_team_name'] ?? 'TBD',
      kickoff: json['kickoff']?.toString(),
      matchId: json['match_id'],
      homeScore: json['home_score'],
      awayScore: json['away_score'],
      isWalkover: json['is_walkover'] == true,
      status: json['status'] ?? 'scheduled',
    );
  }

  bool get isCompleted => status == 'completed';
}

class LeagueService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, String>> _getHeaders(String token) async {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Token $token',
    };
  }

  static Future<List<Map<String, dynamic>>> getLeagues(String token, {bool forceRefresh = false}) async {
    try {
      final leagues = await CacheService.cachedFetch<List<dynamic>>(
        key: '${CacheService.leaguesKey}_all',
        cacheMinutes: 5,
        forceRefresh: forceRefresh,
        fetch: () async {
          final headers = await _getHeaders(token);
          final response = await http.get(
            Uri.parse('$_baseUrl/leagues/'),
            headers: headers,
          ).timeout(ApiConfig.httpTimeout);

          if (response.statusCode != 200) {
            throw Exception('Server returned ${response.statusCode}');
          }
          final data = json.decode(response.body);
          return List<dynamic>.from(data['leagues'] ?? const []);
        },
      );
      return List<Map<String, dynamic>>.from(leagues);
    } catch (e) {
      debugPrint('Error fetching leagues: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getMyLeagues(String token) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.get(
        Uri.parse('$_baseUrl/leagues/my/'),
        headers: headers,
      ).timeout(ApiConfig.httpTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['leagues'] ?? []);
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching my leagues: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> getLeagueDetails(String token, int leagueId) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http.get(
        Uri.parse('$_baseUrl/leagues/$leagueId/'),
        headers: headers,
      ).timeout(ApiConfig.httpTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'league': data['league'],
          'standings': data['standings'] ?? [],
          'fixtures': (data['fixtures'] as List<dynamic>? ?? [])
              .map((f) => LeagueFixture.fromJson(f))
              .toList(),
        };
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
      ).timeout(ApiConfig.httpTimeout);

      final data = json.decode(response.body);

      if (response.statusCode == 201) {
        CacheService.invalidateLeagues();
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
      ).timeout(ApiConfig.httpTimeout);

      final data = json.decode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        CacheService.invalidateLeagues();
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Failed to join league'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  // ── Season management ──

  static Future<Map<String, dynamic>> _post(
    String token,
    String path, {
    Map<String, dynamic> body = const {},
  }) async {
    try {
      final headers = await _getHeaders(token);
      final response = await http
          .post(Uri.parse('$_baseUrl$path'), headers: headers, body: json.encode(body))
          .timeout(ApiConfig.httpTimeout);
      final data = json.decode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        CacheService.invalidateLeagues();
        return {'success': true, ...data};
      }
      return {'success': false, 'error': data['error'] ?? 'Failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> startLeague(String token, int leagueId) =>
      _post(token, '/leagues/$leagueId/start/');

  static Future<Map<String, dynamic>> cancelLeague(String token, int leagueId) =>
      _post(token, '/leagues/$leagueId/cancel/');

  static Future<Map<String, dynamic>> removeTeam({
    required String token,
    required int leagueId,
    required int teamId,
  }) =>
      _post(token, '/leagues/$leagueId/remove-team/', body: {'team_id': teamId});

  static Future<Map<String, dynamic>> recordFixtureResult({
    required String token,
    required int fixtureId,
    required int homeScore,
    required int awayScore,
    String walkover = '',
  }) =>
      _post(token, '/leagues/fixtures/$fixtureId/result/', body: {
        'home_score': homeScore,
        'away_score': awayScore,
        if (walkover.isNotEmpty) 'walkover': walkover,
      });

  static Future<Map<String, dynamic>> rescheduleFixture({
    required String token,
    required int fixtureId,
    required DateTime kickoff,
  }) =>
      _post(token, '/leagues/fixtures/$fixtureId/reschedule/',
          body: {'kickoff': kickoff.toUtc().toIso8601String()});

  static Future<Map<String, dynamic>> scheduleFixture({
    required String token,
    required int fixtureId,
    DateTime? dateTime,
    int? venueId,
    String? location,
  }) =>
      _post(token, '/leagues/fixtures/$fixtureId/schedule/', body: {
        if (dateTime != null) 'date_time': dateTime.toUtc().toIso8601String(),
        if (venueId != null) 'venue_id': venueId,
        if (location != null && location.isNotEmpty) 'location': location,
      });
}
