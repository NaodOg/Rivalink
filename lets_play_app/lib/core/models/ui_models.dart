class HomeBundle {
  final List<dynamic> upcomingMatches;
  final List<dynamic> venues;
  final List<dynamic> leagues;
  final List<dynamic> teams;
  final List<dynamic> forYou;

  const HomeBundle({
    required this.upcomingMatches,
    required this.venues,
    required this.leagues,
    required this.teams,
    this.forYou = const [],
  });
}
