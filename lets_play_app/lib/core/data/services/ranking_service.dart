import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_config.dart';

class RankingService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, dynamic>> getIndividualRankings({
    required String token,
    String? sport,
  }) async {
    try {
      final params = <String, String>{};
      if (sport != null && sport.isNotEmpty) params['sport'] = sport;
      final uri = Uri.parse('$_baseUrl/rankings/individual/').replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: {'Authorization': 'Token $token'});
      if (response.statusCode == 200) {
        return {'success': true, 'rankings': json.decode(response.body)['rankings'] ?? []};
      }
      return {'success': false, 'rankings': []};
    } catch (e) {
      return {'success': false, 'rankings': []};
    }
  }

  static Future<Map<String, dynamic>> getTeamRankings({
    required String token,
    String? sport,
  }) async {
    try {
      final params = <String, String>{};
      if (sport != null && sport.isNotEmpty) params['sport'] = sport;
      final uri = Uri.parse('$_baseUrl/rankings/teams/').replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: {'Authorization': 'Token $token'});
      if (response.statusCode == 200) {
        return {'success': true, 'rankings': json.decode(response.body)['rankings'] ?? []};
      }
      return {'success': false, 'rankings': []};
    } catch (e) {
      return {'success': false, 'rankings': []};
    }
  }

  static Future<Map<String, dynamic>> getUserElo({
    required String token,
    required int userId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/rankings/user/$userId/'),
        headers: {'Authorization': 'Token $token'},
      );
      if (response.statusCode == 200) {
        return {'success': true, 'ratings': json.decode(response.body)['ratings'] ?? []};
      }
      return {'success': false, 'ratings': []};
    } catch (e) {
      return {'success': false, 'ratings': []};
    }
  }
}
