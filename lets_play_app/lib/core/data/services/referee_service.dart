import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_config.dart';
import 'auth_service.dart';

class Referee {
  final int id;
  final int userId;
  final String name;
  final List<String> sports;
  final int experienceYears;
  final String bio;
  final double hourlyRate;
  final String location;
  final bool isAvailable;
  final double averageRating;
  final int totalMatches;

  Referee({
    required this.id,
    required this.userId,
    required this.name,
    required this.sports,
    required this.experienceYears,
    required this.bio,
    required this.hourlyRate,
    required this.location,
    required this.isAvailable,
    required this.averageRating,
    required this.totalMatches,
  });

  factory Referee.fromJson(Map<String, dynamic> j) => Referee(
        id: j['id'] ?? 0,
        userId: j['user_id'] ?? 0,
        name: j['name'] ?? '',
        sports: List<String>.from(j['sports'] ?? const []),
        experienceYears: j['experience_years'] ?? 0,
        bio: j['bio'] ?? '',
        hourlyRate: (j['hourly_rate'] ?? 0).toDouble(),
        location: j['location'] ?? '',
        isAvailable: j['is_available'] ?? true,
        averageRating: (j['average_rating'] ?? 0).toDouble(),
        totalMatches: j['total_matches'] ?? 0,
      );
}

class RefereeBooking {
  final int id;
  final String refereeName;
  final int? matchId;
  final String? matchTitle;
  final String status;
  final double fee;
  final String createdAt;

  RefereeBooking({
    required this.id,
    required this.refereeName,
    this.matchId,
    this.matchTitle,
    required this.status,
    required this.fee,
    required this.createdAt,
  });

  factory RefereeBooking.fromJson(Map<String, dynamic> j) => RefereeBooking(
        id: j['id'] ?? 0,
        refereeName: j['referee_name'] ?? '',
        matchId: j['match_id'],
        matchTitle: j['match_title'],
        status: j['status'] ?? 'pending',
        fee: (j['fee'] ?? 0).toDouble(),
        createdAt: j['created_at'] ?? '',
      );
}

class RefereeService {
  RefereeService._();

  static Future<Map<String, String>?> _auth() async {
    final session = await AuthService.getSession();
    final token = session?['token'] as String?;
    if (token == null) return null;
    return {'Content-Type': 'application/json', 'Authorization': 'Token $token'};
  }

  static Future<List<Referee>> list({String? sport}) async {
    try {
      var url = '${ApiConfig.baseUrl}/referees/';
      if (sport != null && sport.isNotEmpty) url += '?sport=$sport';
      final r = await http.get(Uri.parse(url)).timeout(ApiConfig.httpTimeout);
      if (r.statusCode == 200) {
        final data = json.decode(r.body);
        return (data['referees'] as List<dynamic>? ?? [])
            .map((e) => Referee.fromJson(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>> book({required int refereeId, required int matchId}) async {
    try {
      final h = await _auth();
      if (h == null) return {'success': false, 'error': 'Not logged in'};
      final r = await http
          .post(Uri.parse('${ApiConfig.baseUrl}/referees/book/'),
              headers: h, body: json.encode({'referee_id': refereeId, 'match_id': matchId}))
          .timeout(ApiConfig.httpTimeout);
      final data = json.decode(r.body);
      if (r.statusCode == 201) return {'success': true, 'booking': data['booking']};
      return {'success': false, 'error': data['error'] ?? 'Failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Future<List<RefereeBooking>> myBookings({bool asReferee = false}) async {
    try {
      final h = await _auth();
      if (h == null) return [];
      final url = '${ApiConfig.baseUrl}/referees/bookings/?as=${asReferee ? 'referee' : 'booker'}';
      final r = await http.get(Uri.parse(url), headers: h).timeout(ApiConfig.httpTimeout);
      if (r.statusCode == 200) {
        final data = json.decode(r.body);
        return (data['bookings'] as List<dynamic>? ?? [])
            .map((e) => RefereeBooking.fromJson(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>> updateStatus(int bookingId, String status) async {
    try {
      final h = await _auth();
      if (h == null) return {'success': false, 'error': 'Not logged in'};
      final r = await http
          .post(Uri.parse('${ApiConfig.baseUrl}/referees/bookings/$bookingId/'),
              headers: h, body: json.encode({'status': status}))
          .timeout(ApiConfig.httpTimeout);
      final data = json.decode(r.body);
      return {'success': r.statusCode == 200, 'error': data['error']};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }
}
