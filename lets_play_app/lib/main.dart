import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/navigation/app_routes.dart';
import 'core/data/repositories/app_repository.dart';
import 'core/state/session_controller.dart';
import 'core/theme/rivalink_theme.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/add_field_screen.dart';
import 'ui/screens/chat_screen.dart';
import 'ui/screens/field_details_screen.dart';
import 'ui/screens/host_match_screen.dart';
import 'ui/screens/create_league_screen.dart';
import 'ui/screens/league_details_screen.dart';
import 'ui/screens/match_details_screen.dart';
import 'ui/screens/my_bookings_screen.dart';
import 'ui/screens/notifications_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/payments_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/edit_profile_screen.dart';
import 'ui/screens/shell_screen.dart';
import 'ui/screens/ranking_screen.dart';
import 'ui/screens/friends_screen.dart';
import 'ui/screens/tournaments_screen.dart';
import 'ui/screens/tournament_detail_screen.dart';
import 'ui/screens/venue_dashboard_screen.dart';
import 'ui/screens/referee_screen.dart';
import 'ui/screens/my_teams_screen.dart';
import 'ui/screens/phone_verify_screen.dart';
import 'core/l10n/l10n.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/screens/team_details_screen.dart';
import 'ui/screens/subscription_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RivalinkApp());
}

class RivalinkApp extends StatefulWidget {
  const RivalinkApp({super.key});

  @override
  State<RivalinkApp> createState() => _RivalinkAppState();
}

class _RivalinkAppState extends State<RivalinkApp> {
  final AppRepository _repo = AppRepository();
  late final SessionController _session = SessionController(_repo);

  @override
  void initState() {
    super.initState();
    L10n.load();
    _session.bootstrap();
  }

  Route<dynamic> _route(RouteSettings settings) {
    final args = settings.arguments;
    switch (settings.name) {
      case AppRoutes.splash:
        return MaterialPageRoute(builder: (_) => SplashScreen(session: _session));
      case AppRoutes.onboarding:
        return MaterialPageRoute(builder: (_) => const OnboardingScreen());
      case AppRoutes.auth:
        return MaterialPageRoute(builder: (_) => AuthScreen(session: _session));
      case AppRoutes.shell:
        return MaterialPageRoute(builder: (_) => ShellScreen(session: _session, repo: _repo));
      case AppRoutes.home:
        return MaterialPageRoute(builder: (_) => ShellScreen(session: _session, repo: _repo, initialIndex: 0));
      case AppRoutes.exploreMatches:
        return MaterialPageRoute(builder: (_) => ShellScreen(session: _session, repo: _repo, initialIndex: 1));
      case AppRoutes.matchDetails:
        return MaterialPageRoute(builder: (_) => MatchDetailsScreen(session: _session, repo: _repo, matchId: args as int));
      case AppRoutes.hostMatch:
        return MaterialPageRoute(builder: (_) => HostMatchScreen(session: _session, repo: _repo));
      case AppRoutes.bookField:
        return MaterialPageRoute(
            builder: (_) => ShellScreen(
                session: _session, repo: _repo, initialIndex: 1, startExploreVenues: true));
      case AppRoutes.addField:
        return MaterialPageRoute(builder: (_) => AddFieldScreen(session: _session, repo: _repo));
      case AppRoutes.fieldDetails:
        return MaterialPageRoute(builder: (_) => FieldDetailsScreen(session: _session, repo: _repo, fieldId: args as int));
      case AppRoutes.myBookings:
        return MaterialPageRoute(builder: (_) => MyBookingsScreen(repo: _repo));
      case AppRoutes.teamDetails:
        final map = args as Map<String, dynamic>;
        return MaterialPageRoute(builder: (_) => TeamDetailsScreen(session: _session, repo: _repo, teamId: map['id'] as int, teamName: map['name'] as String));
      case AppRoutes.leagueDetails:
        final map = args as Map<String, dynamic>;
        return MaterialPageRoute(builder: (_) => LeagueDetailsScreen(session: _session, repo: _repo, leagueId: map['id'] as int, leagueName: map['name'] as String));
      case AppRoutes.createLeague:
        return MaterialPageRoute(builder: (_) => CreateLeagueScreen(session: _session, repo: _repo));
      case AppRoutes.leagues:
        return MaterialPageRoute(builder: (_) => ShellScreen(session: _session, repo: _repo, initialIndex: 2));
      case AppRoutes.rankings:
        return MaterialPageRoute(builder: (_) => RankingScreen(session: _session, repo: _repo));
      case AppRoutes.friends:
        return MaterialPageRoute(builder: (_) => FriendsScreen(session: _session, repo: _repo));
      case AppRoutes.tournaments:
        return MaterialPageRoute(builder: (_) => TournamentsScreen(session: _session, repo: _repo));
      case AppRoutes.tournamentDetails:
        final map = args as Map<String, dynamic>;
        return MaterialPageRoute(
            builder: (_) => TournamentDetailScreen(
                session: _session,
                repo: _repo,
                tournamentId: map['id'] as int,
                tournamentName: map['name'] as String));
      case AppRoutes.myVenues:
        return MaterialPageRoute(builder: (_) => VenueDashboardScreen(session: _session, repo: _repo));
      case AppRoutes.myTeams:
        return MaterialPageRoute(builder: (_) => MyTeamsScreen(session: _session, repo: _repo));
      case AppRoutes.referees:
        return MaterialPageRoute(builder: (_) => RefereeScreen(session: _session, repo: _repo));
      case AppRoutes.phoneVerify:
        return MaterialPageRoute(builder: (_) => PhoneVerifyScreen(session: _session));
      case AppRoutes.profile:
        return MaterialPageRoute(builder: (_) => ShellScreen(session: _session, repo: _repo, initialIndex: 3));
      case AppRoutes.notifications:
        return MaterialPageRoute(builder: (_) => NotificationsScreen(session: _session, repo: _repo));
      case AppRoutes.chat:
        final map = args as Map<String, dynamic>;
        return MaterialPageRoute(builder: (_) => ChatScreen(
          session: _session,
          repo: _repo,
          matchId: map['matchId'] as int?,
          teamId: map['teamId'] as int?,
          title: map['title'] as String,
        ));
      case AppRoutes.payments:
        return MaterialPageRoute(builder: (_) => const PaymentsScreen());
      case AppRoutes.settings:
        return MaterialPageRoute(builder: (_) => SettingsScreen(session: _session));
      case AppRoutes.subscription:
        return MaterialPageRoute(builder: (_) => SubscriptionScreen(token: _session.token ?? ''));
      case AppRoutes.editProfile:
        return MaterialPageRoute(builder: (_) => EditProfileScreen(session: _session, repo: _repo));
      default:
        return MaterialPageRoute(builder: (_) => SplashScreen(session: _session));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: L10n.locale,
      builder: (context, _, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Rivalink',
        theme: RivalinkTheme.dark,
        initialRoute: AppRoutes.splash,
        onGenerateRoute: _route,
      ),
    );
  }
}

Future<String> resolveInitialRoute(SessionController session) async {
  final prefs = await SharedPreferences.getInstance();
  if (kDebugMode) {
    return session.token == null ? AppRoutes.auth : AppRoutes.shell;
  }
  final done = prefs.getBool('onboarding_done') ?? false;
  if (!done) return AppRoutes.onboarding;
  return session.token == null ? AppRoutes.auth : AppRoutes.shell;
}
