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
import 'core/data/services/analytics_service.dart';
import 'core/navigation/analytics_observer.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/screens/team_details_screen.dart';
import 'ui/screens/subscription_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AnalyticsService.init();
  final session = SessionController(AppRepository());
  await session.hydrate();
  final homeRoute = await resolveInitialRoute(session);
  runApp(RivalinkApp(session: session, homeRoute: homeRoute));
}

class RivalinkApp extends StatefulWidget {
  final SessionController session;
  final String homeRoute;
  const RivalinkApp({super.key, required this.session, required this.homeRoute});

  @override
  State<RivalinkApp> createState() => _RivalinkAppState();
}

class _RivalinkAppState extends State<RivalinkApp> {
  final AppRepository _repo = AppRepository();
  late final SessionController _session = widget.session;

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
        return MaterialPageRoute(settings: settings, 
            builder: (_) => SplashScreen(session: _session, nextRoute: widget.homeRoute));
      case AppRoutes.onboarding:
        return MaterialPageRoute(settings: settings, builder: (_) => const OnboardingScreen());
      case AppRoutes.auth:
        return MaterialPageRoute(settings: settings, builder: (_) => AuthScreen(session: _session));
      case AppRoutes.shell:
        return MaterialPageRoute(settings: settings, builder: (_) => ShellScreen(session: _session, repo: _repo));
      case AppRoutes.home:
        return MaterialPageRoute(settings: settings, builder: (_) => ShellScreen(session: _session, repo: _repo, initialIndex: 0));
      case AppRoutes.exploreMatches:
        return MaterialPageRoute(settings: settings, builder: (_) => ShellScreen(session: _session, repo: _repo, initialIndex: 1));
      case AppRoutes.matchDetails:
        return MaterialPageRoute(settings: settings, builder: (_) => MatchDetailsScreen(session: _session, repo: _repo, matchId: args as int));
      case AppRoutes.hostMatch:
        return MaterialPageRoute(settings: settings, builder: (_) => HostMatchScreen(session: _session, repo: _repo));
      case AppRoutes.bookField:
        return MaterialPageRoute(settings: settings, 
            builder: (_) => ShellScreen(
                session: _session, repo: _repo, initialIndex: 1, startExploreVenues: true));
      case AppRoutes.addField:
        return MaterialPageRoute(settings: settings, builder: (_) => AddFieldScreen(session: _session, repo: _repo));
      case AppRoutes.fieldDetails:
        return MaterialPageRoute(settings: settings, builder: (_) => FieldDetailsScreen(session: _session, repo: _repo, fieldId: args as int));
      case AppRoutes.myBookings:
        return MaterialPageRoute(settings: settings, builder: (_) => MyBookingsScreen(repo: _repo));
      case AppRoutes.teamDetails:
        final map = args as Map<String, dynamic>;
        return MaterialPageRoute(settings: settings, builder: (_) => TeamDetailsScreen(session: _session, repo: _repo, teamId: map['id'] as int, teamName: map['name'] as String));
      case AppRoutes.leagueDetails:
        final map = args as Map<String, dynamic>;
        return MaterialPageRoute(settings: settings, builder: (_) => LeagueDetailsScreen(session: _session, repo: _repo, leagueId: map['id'] as int, leagueName: map['name'] as String));
      case AppRoutes.createLeague:
        return MaterialPageRoute(settings: settings, builder: (_) => CreateLeagueScreen(session: _session, repo: _repo));
      case AppRoutes.leagues:
        return MaterialPageRoute(settings: settings, builder: (_) => ShellScreen(session: _session, repo: _repo, initialIndex: 2));
      case AppRoutes.rankings:
        return MaterialPageRoute(settings: settings, builder: (_) => RankingScreen(session: _session, repo: _repo));
      case AppRoutes.friends:
        return MaterialPageRoute(settings: settings, builder: (_) => FriendsScreen(session: _session, repo: _repo));
      case AppRoutes.tournaments:
        return MaterialPageRoute(settings: settings, builder: (_) => TournamentsScreen(session: _session, repo: _repo));
      case AppRoutes.tournamentDetails:
        final map = args as Map<String, dynamic>;
        return MaterialPageRoute(settings: settings, 
            builder: (_) => TournamentDetailScreen(
                session: _session,
                repo: _repo,
                tournamentId: map['id'] as int,
                tournamentName: map['name'] as String));
      case AppRoutes.myVenues:
        return MaterialPageRoute(settings: settings, builder: (_) => VenueDashboardScreen(session: _session, repo: _repo));
      case AppRoutes.myTeams:
        return MaterialPageRoute(settings: settings, builder: (_) => MyTeamsScreen(session: _session, repo: _repo));
      case AppRoutes.referees:
        return MaterialPageRoute(settings: settings, builder: (_) => RefereeScreen(session: _session, repo: _repo));
      case AppRoutes.phoneVerify:
        return MaterialPageRoute(settings: settings, builder: (_) => PhoneVerifyScreen(session: _session));
      case AppRoutes.profile:
        return MaterialPageRoute(settings: settings, builder: (_) => ShellScreen(session: _session, repo: _repo, initialIndex: 3));
      case AppRoutes.notifications:
        return MaterialPageRoute(settings: settings, builder: (_) => NotificationsScreen(session: _session, repo: _repo));
      case AppRoutes.chat:
        final map = args as Map<String, dynamic>;
        return MaterialPageRoute(settings: settings, builder: (_) => ChatScreen(
          session: _session,
          repo: _repo,
          matchId: map['matchId'] as int?,
          teamId: map['teamId'] as int?,
          title: map['title'] as String,
        ));
      case AppRoutes.payments:
        return MaterialPageRoute(settings: settings, builder: (_) => const PaymentsScreen());
      case AppRoutes.settings:
        return MaterialPageRoute(settings: settings, builder: (_) => SettingsScreen(session: _session));
      case AppRoutes.subscription:
        final token = _session.token;
        if (token == null) {
          return MaterialPageRoute(settings: settings, builder: (_) => AuthScreen(session: _session));
        }
        return MaterialPageRoute(settings: settings, builder: (_) => SubscriptionScreen(token: token));
      case AppRoutes.editProfile:
        return MaterialPageRoute(settings: settings, builder: (_) => EditProfileScreen(session: _session, repo: _repo));
      default:
        return MaterialPageRoute(settings: settings, builder: (_) => AuthScreen(session: _session));
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
        navigatorObservers: [AnalyticsObserver()],
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
