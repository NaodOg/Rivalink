import 'package:flutter/material.dart';

import '../../core/data/services/analytics_service.dart';

/// Automatically tracks screen views and time spent per screen.
class AnalyticsObserver extends NavigatorObserver {
  final Map<Route<dynamic>, DateTime> _started = {};
  final Map<Route<dynamic>, String> _names = {};

  static const Map<String, String> _labels = {
    '/': 'Splash',
    '/onboarding': 'Onboarding',
    '/auth': 'Auth',
    '/shell': 'Home',
    '/home': 'Home',
    '/matches': 'Explore',
    '/match-details': 'Match details',
    '/host-match': 'Host match',
    '/add-field': 'Add venue',
    '/field-details': 'Venue details',
    '/my-bookings': 'My bookings',
    '/team-details': 'Team details',
    '/league-details': 'League details',
    '/create-league': 'Create league',
    '/leagues': 'Leagues',
    '/rankings': 'Rankings',
    '/friends': 'Friends',
    '/tournaments': 'Tournaments',
    '/tournament-details': 'Tournament details',
    '/my-venues': 'Venue dashboard',
    '/my-teams': 'My teams',
    '/referees': 'Referees',
    '/phone-verify': 'Phone verification',
    '/profile': 'Profile',
    '/notifications': 'Notifications',
    '/chat': 'Chat',
    '/payments': 'Payments',
    '/host-earnings': 'Host earnings',
    '/credits': 'Credits',
    '/settings': 'Settings',
    '/subscription': 'Premium',
    '/edit-profile': 'Edit profile',
  };

  String? _screenFor(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || name.isEmpty) return null;
    return _labels[name] ?? name.replaceAll('/', '');
  }

  void _enter(Route<dynamic> route) {
    final screen = _screenFor(route);
    if (screen == null) return;
    _started[route] = DateTime.now();
    _names[route] = screen;
    AnalyticsService.screen(screen);
  }

  void _exit(Route<dynamic> route) {
    final screen = _names.remove(route);
    final start = _started.remove(route);
    if (screen == null || start == null) return;
    AnalyticsService.screenExit(
        screen, DateTime.now().difference(start).inMilliseconds);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _enter(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _exit(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _exit(oldRoute);
    if (newRoute != null) _enter(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _exit(route);
  }
}
