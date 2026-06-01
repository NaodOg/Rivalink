import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class Tournament {
  final int id;
  final String name;
  final String sport;
  final String description;
  final String format;
  final String formatDisplay;
  final String prizePool;
  final double entryFee;
  final int maxTeams;
  final int currentTeams;
  final int rounds;
  final String status;
  final String statusDisplay;
  final String? startDate;
  final String? endDate;
  final int organizerId;
  final String organizerName;
  final int? venueId;
  final String? venueName;
  final String location;
  final String rules;
  final bool isPublic;
  final String createdAt;

  Tournament({
    required this.id,
    required this.name,
    required this.sport,
    required this.description,
    required this.format,
    required this.formatDisplay,
    required this.prizePool,
    required this.entryFee,
    required this.maxTeams,
    required this.currentTeams,
    required this.rounds,
    required this.status,
    required this.statusDisplay,
    this.startDate,
    this.endDate,
    required this.organizerId,
    required this.organizerName,
    this.venueId,
    this.venueName,
    required this.location,
    required this.rules,
    required this.isPublic,
    required this.createdAt,
  });

  factory Tournament.fromJson(Map<String, dynamic> json) {
    return Tournament(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      sport: json['sport'] ?? 'other',
      description: json['description'] ?? '',
      format: json['format'] ?? 'single_elimination',
      formatDisplay: json['format_display'] ?? 'Single Elimination',
      prizePool: json['prize_pool'] ?? '',
      entryFee: (json['entry_fee'] ?? 0).toDouble(),
      maxTeams: json['max_teams'] ?? 8,
      currentTeams: json['current_teams'] ?? 0,
      rounds: json['rounds'] ?? 3,
      status: json['status'] ?? 'draft',
      statusDisplay: json['status_display'] ?? 'Draft',
      startDate: json['start_date'],
      endDate: json['end_date'],
      organizerId: json['organizer_id'] ?? 0,
      organizerName: json['organizer_name'] ?? '',
      venueId: json['venue_id'],
      venueName: json['venue_name'],
      location: json['location'] ?? '',
      rules: json['rules'] ?? '',
      isPublic: json['is_public'] ?? true,
      createdAt: json['created_at'] ?? '',
    );
  }
}

class TournamentTeam {
  final int id;
  final int tournamentId;
  final int teamId;
  final String teamName;
  final int seed;
  final String status;
  final int registeredById;
  final String joinedAt;

  TournamentTeam({
    required this.id,
    required this.tournamentId,
    required this.teamId,
    required this.teamName,
    required this.seed,
    required this.status,
    required this.registeredById,
    required this.joinedAt,
  });

  factory TournamentTeam.fromJson(Map<String, dynamic> json) {
    return TournamentTeam(
      id: json['id'] ?? 0,
      tournamentId: json['tournament_id'] ?? 0,
      teamId: json['team_id'] ?? 0,
      teamName: json['team_name'] ?? '',
      seed: json['seed'] ?? 0,
      status: json['status'] ?? 'registered',
      registeredById: json['registered_by_id'] ?? 0,
      joinedAt: json['joined_at'] ?? '',
    );
  }
}

class TournamentMatch {
  final int id;
  final int tournamentId;
  final int roundNumber;
  final int matchNumber;
  final int? team1Id;
  final String team1Name;
  final int? team1Seed;
  final int? team2Id;
  final String team2Name;
  final int? team2Seed;
  final int? winnerId;
  final int score1;
  final int score2;
  final String? scheduledTime;
  final String status;
  final String bracketPosition;

  TournamentMatch({
    required this.id,
    required this.tournamentId,
    required this.roundNumber,
    required this.matchNumber,
    this.team1Id,
    required this.team1Name,
    this.team1Seed,
    this.team2Id,
    required this.team2Name,
    this.team2Seed,
    this.winnerId,
    required this.score1,
    required this.score2,
    this.scheduledTime,
    required this.status,
    required this.bracketPosition,
  });

  factory TournamentMatch.fromJson(Map<String, dynamic> json) {
    return TournamentMatch(
      id: json['id'] ?? 0,
      tournamentId: json['tournament_id'] ?? 0,
      roundNumber: json['round_number'] ?? 1,
      matchNumber: json['match_number'] ?? 1,
      team1Id: json['team1_id'],
      team1Name: json['team1_name'] ?? 'TBD',
      team1Seed: json['team1_seed'],
      team2Id: json['team2_id'],
      team2Name: json['team2_name'] ?? 'TBD',
      team2Seed: json['team2_seed'],
      winnerId: json['winner_id'],
      score1: json['score1'] ?? 0,
      score2: json['score2'] ?? 0,
      scheduledTime: json['scheduled_time'],
      status: json['status'] ?? 'pending',
      bracketPosition: json['bracket_position'] ?? '',
    );
  }

  String get roundDisplayName {
    switch (roundNumber) {
      case 1:
        return 'Round 1';
      case 2:
        return 'Semifinals';
      case 3:
        return 'Finals';
      default:
        return 'Round $roundNumber';
    }
  }
}

class TournamentService {
  static String get _baseUrl {
    if (Platform.isAndroid) {
      return 'https://unpossessively-pseudonational-shawnta.ngrok-free.dev/api';
    }
    return 'https://unpossessively-pseudonational-shawnta.ngrok-free.dev/api';
  }

  static Future<Map<String, String>?> _getAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) return null;
      return {
        'Content-Type': 'application/json',
        'Authorization': 'Token $token',
      };
    } catch (e) {
      return null;
    }
  }

  static Future<List<Tournament>> getTournaments({String? sport, String? status}) async {
    try {
      String url = '$_baseUrl/tournaments/';
      final params = <String>[];
      if (sport != null && sport.isNotEmpty) params.add('sport=$sport');
      if (status != null && status.isNotEmpty) params.add('status=$status');
      if (params.isNotEmpty) url += '?${params.join('&')}';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> tournamentsJson = data['tournaments'] ?? [];
        return tournamentsJson.map((t) => Tournament.fromJson(t)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching tournaments: $e');
      return [];
    }
  }

  static Future<Tournament?> getTournament(int tournamentId) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/tournaments/$tournamentId/'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return Tournament.fromJson(data['tournament']);
      }
      return null;
    } catch (e) {
      print('Error fetching tournament: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> getTournamentDetails(int tournamentId) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/tournaments/$tournamentId/'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'tournament': Tournament.fromJson(data['tournament']),
          'teams': (data['teams'] as List<dynamic>?)
              ?.map((t) => TournamentTeam.fromJson(t))
              .toList() ?? [],
          'matches': (data['matches'] as List<dynamic>?)
              ?.map((m) => TournamentMatch.fromJson(m))
              .toList() ?? [],
        };
      }
      return {'success': false, 'error': 'Failed to load tournament'};
    } catch (e) {
      print('Error fetching tournament details: $e');
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<List<Tournament>> getMyTournaments() async {
    try {
      final headers = await _getAuth();
      if (headers == null) return [];

      final response = await http.get(
        Uri.parse('$_baseUrl/tournaments/my/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> tournamentsJson = data['tournaments'] ?? [];
        return tournamentsJson.map((t) => Tournament.fromJson(t)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching my tournaments: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> createTournament({
    required String name,
    required String sport,
    String description = '',
    String format = 'single_elimination',
    String prizePool = '',
    double entryFee = 0,
    int maxTeams = 8,
    int rounds = 3,
    String? startDate,
    String location = '',
    String rules = '',
  }) async {
    try {
      final headers = await _getAuth();
      if (headers == null) return {'success': false, 'error': 'Not logged in'};

      final response = await http.post(
        Uri.parse('$_baseUrl/tournaments/create/'),
        headers: headers,
        body: json.encode({
          'name': name,
          'sport': sport,
          'description': description,
          'format': format,
          'prize_pool': prizePool,
          'entry_fee': entryFee,
          'max_teams': maxTeams,
          'rounds': rounds,
          'start_date': startDate,
          'location': location,
          'rules': rules,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 201) {
        return {
          'success': true,
          'tournament': Tournament.fromJson(data['tournament']),
        };
      }
      return {'success': false, 'error': data['error'] ?? 'Failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> registerTeam({
    required int tournamentId,
    required int teamId,
  }) async {
    try {
      final headers = await _getAuth();
      if (headers == null) return {'success': false, 'error': 'Not logged in'};

      final response = await http.post(
        Uri.parse('$_baseUrl/tournaments/register/'),
        headers: headers,
        body: json.encode({
          'tournament_id': tournamentId,
          'team_id': teamId,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 201) {
        return {
          'success': true,
          'team': TournamentTeam.fromJson(data['team']),
        };
      }
      return {'success': false, 'error': data['error'] ?? 'Failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> startTournament(int tournamentId) async {
    try {
      final headers = await _getAuth();
      if (headers == null) return {'success': false, 'error': 'Not logged in'};

      final response = await http.post(
        Uri.parse('$_baseUrl/tournaments/$tournamentId/start/'),
        headers: headers,
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'tournament': Tournament.fromJson(data['tournament']),
        };
      }
      return {'success': false, 'error': data['error'] ?? 'Failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> updateMatchResult({
    required int matchId,
    required int score1,
    required int score2,
  }) async {
    try {
      final headers = await _getAuth();
      if (headers == null) return {'success': false, 'error': 'Not logged in'};

      final response = await http.post(
        Uri.parse('$_baseUrl/tournaments/matches/$matchId/result/'),
        headers: headers,
        body: json.encode({
          'score1': score1,
          'score2': score2,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'match': TournamentMatch.fromJson(data['match']),
        };
      }
      return {'success': false, 'error': data['error'] ?? 'Failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }
}
