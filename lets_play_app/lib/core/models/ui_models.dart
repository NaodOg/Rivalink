class HomeBundle {
  final List<dynamic> upcomingMatches;
  final List<dynamic> venues;
  final List<dynamic> leagues;
  final List<dynamic> teams;

  const HomeBundle({
    required this.upcomingMatches,
    required this.venues,
    required this.leagues,
    required this.teams,
  });
}

class AppStats {
  final int matchesPlayed;
  final int goals;
  final int assists;
  final int winRate;
  final int xp;

  const AppStats({
    required this.matchesPlayed,
    required this.goals,
    required this.assists,
    required this.winRate,
    required this.xp,
  });
}
