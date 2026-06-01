import '../models/match.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/league_service.dart';
import '../services/match_service.dart';
import '../services/notification_service.dart';
import '../services/team_service.dart';
import '../services/tournament_service.dart';
import '../services/user_stats_service.dart';
import '../services/venue_service.dart';
import '../services/ranking_service.dart';
import '../../data/seed_data.dart';
import '../../models/ui_models.dart';

class AppRepository {
  Future<Map<String, dynamic>?> getSession() => AuthService.getSession();

  Future<Map<String, dynamic>> login(String email, String password) {
    return AuthService.login(email: email, password: password);
  }

  Future<Map<String, dynamic>> signup({
    required String name,
    required String phone,
    required String email,
    required String password,
    String location = '',
  }) {
    return AuthService.signup(name: name, phone: phone, email: email, password: password, location: location);
  }

  Future<void> saveSession(String token, Map<String, dynamic> user) {
    return AuthService.saveSession(token, user);
  }

  Future<void> clearSession() => AuthService.clearSession();

  Future<HomeBundle> getHomeBundle(String token) async {
    final matches = await MatchService.getMatches(token);
    final venues = await VenueService.getVenues();
    final leagues = await LeagueService.getLeagues(token);
    final teams = await TeamService.getMyTeams(token);

    return HomeBundle(
      upcomingMatches: matches,
      venues: venues.isEmpty ? SeedData.fields : venues,
      leagues: leagues.isEmpty ? SeedData.leagues : leagues,
      teams: teams,
    );
  }

  Future<List<PlayFairMatch>> getMatches(String token, {bool forceRefresh = false}) => MatchService.getMatches(token, forceRefresh: forceRefresh);

  Future<List<PlayFairMatch>> getMyMatches(String token, {required String role, required String status}) {
    return MatchService.getMyMatches(token, role: role, status: status);
  }

  Future<Map<String, dynamic>> getMatchDetails(String token, int matchId) {
    return MatchService.getMatchDetails(token: token, matchId: matchId);
  }

  Future<Map<String, dynamic>> createMatch({
    required String token,
    required String title,
    required String sport,
    required String location,
    required DateTime dateTime,
    required int maxPlayers,
    required double price,
    String description = '',
  }) {
    return MatchService.createMatch(
      token: token,
      title: title,
      sport: sport,
      description: description,
      location: location,
      dateTime: dateTime,
      maxPlayers: maxPlayers,
      price: price,
    );
  }

  Future<Map<String, dynamic>> joinMatch(String token, int matchId) {
    return MatchService.joinMatch(token: token, matchId: matchId);
  }

  Future<List<Venue>> getFields({String? sport}) => VenueService.getVenues(sport: sport);

  Future<Map<String, dynamic>> createField({
    required String token,
    required String name,
    required String description,
    required String address,
    required String city,
    required String location,
    required String sports,
    required double pricePerHour,
    required int capacity,
    required String amenities,
    String? openingTime,
    String? closingTime,
    dynamic image,
  }) {
    return VenueService.createVenue(
      name: name,
      address: address,
      city: city,
      description: description,
      sports: sports,
      pricePerHour: pricePerHour,
      capacity: capacity,
      amenities: amenities,
      openingTime: openingTime,
      closingTime: closingTime,
      imagePath: image?.path,
    );
  }

  Future<Venue?> getField(int id) => VenueService.getVenue(id);

  Future<Map<String, dynamic>> bookField({
    required int venueId,
    required String date,
    required String start,
    required String end,
  }) {
    return VenueService.bookVenue(venueId: venueId, date: date, startTime: start, endTime: end);
  }

  Future<Map<String, dynamic>> updateProfile({
    required String token,
    String? name,
    String? email,
    String? profileImage,
    String? bio,
    String? location,
    List<String>? favoriteSports,
  }) {
    return AuthService.updateProfile(
      token: token,
      name: name,
      email: email,
      profileImage: profileImage,
      bio: bio,
      location: location,
      favoriteSports: favoriteSports,
    );
  }

  Future<Map<String, dynamic>> uploadProfileImage({
    required String token,
    required String imagePath,
  }) {
    return AuthService.uploadProfileImage(token: token, imagePath: imagePath);
  }

  Future<List<VenueBooking>> getBookings() => VenueService.getVenueBookings(asOwner: false);

  Future<List<dynamic>> getMyTeams(String token) => TeamService.getMyTeams(token);

  Future<Map<String, dynamic>> createTeam({
    required String token,
    required String name,
    required String sport,
    required String location,
    required int maxMembers,
  }) {
    return TeamService.createTeam(
      token: token,
      name: name,
      sport: sport,
      location: location,
      maxMembers: maxMembers,
      isSeekingPlayers: true,
    );
  }

  Future<Map<String, dynamic>> getTeamMembers(String token, int teamId) {
    return TeamService.getTeamMembersApi(token: token, teamId: teamId);
  }

  Future<Map<String, dynamic>> getJoinRequests(String token, int teamId) {
    return TeamService.getJoinRequests(token: token, teamId: teamId);
  }

  Future<List<Map<String, dynamic>>> getLeagues(String token) => LeagueService.getLeagues(token);

  Future<Map<String, dynamic>> getLeagueDetails(String token, int leagueId) {
    return LeagueService.getLeagueDetails(token, leagueId);
  }

  Future<Map<String, dynamic>> createLeague({
    required String token,
    required String name,
    required String sport,
    String format = '5v5',
    int maxTeams = 8,
    double entryFee = 0,
    String prize = '',
    String location = '',
    required DateTime startDate,
  }) {
    return LeagueService.createLeague(
      token: token,
      name: name,
      sport: sport,
      format: format,
      maxTeams: maxTeams,
      entryFee: entryFee,
      prize: prize,
      location: location,
      startDate: startDate,
    );
  }

  Future<Map<String, dynamic>> joinLeague(String token, int leagueId, int teamId) {
    return LeagueService.joinLeague(token: token, leagueId: leagueId, teamId: teamId);
  }

  Future<List<Tournament>> getTournaments() => TournamentService.getTournaments();

  Future<Map<String, dynamic>> getTournamentDetails(int id) => TournamentService.getTournamentDetails(id);

  Future<Map<String, dynamic>> getProfileStats(String token, int userId) {
    return UserStatsService.getUserStats(token, userId);
  }

  Future<Map<String, dynamic>> getNotifications(String token) {
    return NotificationService.getNotifications(token);
  }

  Future<Map<String, dynamic>> markNotificationsRead(String token) {
    return NotificationService.markAsRead(token: token);
  }

  Future<Map<String, dynamic>> submitMatchResult({
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
  }) {
    return MatchService.submitMatchResult(
      token: token,
      matchId: matchId,
      matchType: matchType,
      resultType: resultType,
      winnerTeamId: winnerTeamId,
      winnerUserId: winnerUserId,
      winningGroup: winningGroup,
      mvpUserId: mvpUserId,
      score: score,
      notes: notes,
      teamGroups: teamGroups,
    );
  }

  Future<List<ChatMessage>> getMatchChat(String token, int matchId) {
    return ChatService.getMatchChat(token: token, matchId: matchId);
  }

  Future<Map<String, dynamic>> sendMatchChat(String token, int matchId, String message) {
    return ChatService.sendMessage(token: token, matchId: matchId, message: message);
  }
}
