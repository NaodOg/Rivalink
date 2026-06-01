import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/playfair_theme.dart';
import '../../core/data/services/venue_service.dart';
import '../widgets/bottom_tab_bar.dart';
import '../widgets/field_card.dart';
import '../widgets/filter_chips_row.dart';
import '../widgets/league_card.dart';
import '../widgets/match_card.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/profile_header.dart';
import '../widgets/search_header.dart';
import '../widgets/notification_bell.dart';
import 'ranking_screen.dart';
import '../../core/data/models/match.dart';
import '../../core/data/services/ranking_service.dart';

class ShellScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  final int initialIndex;
  const ShellScreen({super.key, required this.session, required this.repo, this.initialIndex = 0});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  late int _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomeTab(session: widget.session, repo: widget.repo),
      _MatchesTab(session: widget.session, repo: widget.repo),
      _FieldsTab(session: widget.session, repo: widget.repo),
      _LeaguesTab(session: widget.session, repo: widget.repo),
      RankingScreen(session: widget.session, repo: widget.repo),
      _ProfileTab(session: widget.session, repo: widget.repo),
    ];

    return Scaffold(
      backgroundColor: PFColors.background,
      body: pages[_tab],
      bottomNavigationBar: BottomTabBar(index: _tab, onChanged: (i) => setState(() => _tab = i)),
    );
  }
}

class _HomeTab extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const _HomeTab({required this.session, required this.repo});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  List<PlayFairMatch> _matches = [];
  List<Venue> _fields = [];
  List<Map<String, dynamic>> _leagues = [];
  bool _loading = true;
  bool _error = false;
  String? get _profileImage => widget.session.user?['profile_image']?.toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() { _loading = true; _error = false; });
    try {
      final bundle = await widget.repo.getHomeBundle(token);
      if (!mounted) return;
      setState(() {
        _matches = List<PlayFairMatch>.from(bundle.upcomingMatches.take(3));
        _fields = List<Venue>.from(bundle.venues.take(3));
        _leagues = List<Map<String, dynamic>>.from(bundle.leagues.take(3));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: PFColors.accent,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('PlayFair', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                ),
                NotificationBell(session: widget.session, repo: widget.repo),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: PFColors.card,
                    backgroundImage: _profileImage != null && _profileImage!.isNotEmpty
                        ? NetworkImage(_profileImage!)
                        : null,
                    child: (_profileImage == null || _profileImage!.isEmpty)
                        ? const Icon(Icons.person_rounded, color: PFColors.text, size: 20)
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const SearchHeader(hint: 'Search for fields, matches, players...'),
            const SizedBox(height: 14),
            PFCard(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 260,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          'assets/images/hero_soccer.jpg',
                          fit: BoxFit.cover,
                          alignment: Alignment.centerRight,
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                PFColors.background.withValues(alpha: 0.92),
                                PFColors.background.withValues(alpha: 0.66),
                                PFColors.background.withValues(alpha: 0.12),
                              ],
                              stops: const [0.0, 0.46, 1.0],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 108, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Text(
                              'Play. Connect. Compete.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.0),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Book fields, join matches, and build your sports circle in Addis Ababa.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.3),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: 150,
                              child: PFButton(
                                label: 'Find a Field',
                                onTap: () => Navigator.pushNamed(context, AppRoutes.bookField),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_error)
              _RetryBanner(onRetry: _load)
            else ...[
              const SizedBox(height: 18),
              _SectionHeader(title: 'Upcoming Matches', action: 'View all', onTap: () => Navigator.pushNamed(context, AppRoutes.exploreMatches)),
              const SizedBox(height: 8),
              if (_loading) const _LoadingMini() else ..._matches.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: MatchCard(match: m, onTap: () => Navigator.pushNamed(context, AppRoutes.matchDetails, arguments: int.tryParse(m.id) ?? 1)),
              )),
              const SizedBox(height: 6),
              _SectionHeader(title: 'Nearby Fields', action: 'Book', onTap: () => Navigator.pushNamed(context, AppRoutes.bookField)),
              const SizedBox(height: 8),
              ..._fields.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FieldCard(venue: f, onTap: () => Navigator.pushNamed(context, AppRoutes.fieldDetails, arguments: f.id)),
              )),
              const SizedBox(height: 6),
              _SectionHeader(title: 'Active Leagues', action: 'Join', onTap: () => Navigator.pushNamed(context, AppRoutes.leagues)),
              const SizedBox(height: 8),
              ..._leagues.map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LeagueCard(league: l, onTap: () => Navigator.pushNamed(context, AppRoutes.leagueDetails, arguments: {'id': l['id'] ?? 1, 'name': l['name'] ?? 'League'})),
              )),
            ],
          ],
        ),
      ),
    );
  }
}

class _MatchesTab extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const _MatchesTab({required this.session, required this.repo});

  @override
  State<_MatchesTab> createState() => _MatchesTabState();
}

class _MatchesTabState extends State<_MatchesTab> {
  List<PlayFairMatch> _matches = [];
  bool _loading = true;
  bool _error = false;
  String? get _profileImage => widget.session.user?['profile_image']?.toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() { _loading = true; _error = false; });
    try {
      final matches = await widget.repo.getMatches(token, forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => _load(forceRefresh: true),
        color: PFColors.accent,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Explore Matches', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                ),
                NotificationBell(session: widget.session, repo: widget.repo),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: PFColors.card,
                    backgroundImage: _profileImage != null && _profileImage!.isNotEmpty
                        ? NetworkImage(_profileImage!)
                        : null,
                    child: (_profileImage == null || _profileImage!.isEmpty)
                        ? const Icon(Icons.person_rounded, color: PFColors.text, size: 20)
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const SearchHeader(hint: '5v5 football near Bole'),
            const SizedBox(height: 10),
            FilterChipsRow(labels: const ['All', 'Football', 'Basketball', 'Tennis'], selected: 'All', onSelected: (_) {}),
            const SizedBox(height: 10),
            PFButton(label: 'Host Match', onTap: () => Navigator.pushNamed(context, AppRoutes.hostMatch)),
            const SizedBox(height: 14),
            if (_loading)
              const _LoadingMini()
            else if (_error)
              _RetryBanner(onRetry: () => _load(forceRefresh: true))
            else if (_matches.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('No matches found.', style: TextStyle(color: PFColors.muted))),
              )
            else
              ..._matches.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: MatchCard(match: m, onTap: () => Navigator.pushNamed(context, AppRoutes.matchDetails, arguments: int.tryParse(m.id) ?? 1)),
              )),
          ],
        ),
      ),
    );
  }
}

class _RetryBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const _RetryBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: PFColors.muted),
          const SizedBox(height: 12),
          const Text('Could not load matches. Check your connection.', textAlign: TextAlign.center, style: TextStyle(color: PFColors.muted)),
          const SizedBox(height: 16),
          PFButton(label: 'Retry', onTap: onRetry),
        ],
      ),
    );
  }
}

class _FieldsTab extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const _FieldsTab({required this.session, required this.repo});

  @override
  State<_FieldsTab> createState() => _FieldsTabState();
}

class _FieldsTabState extends State<_FieldsTab> {
  List<Venue> _fields = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = false; });
    try {
      final fields = await widget.repo.getFields();
      if (!mounted) return;
      setState(() {
        _fields = fields;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            color: PFColors.accent,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                const Center(child: Text('Book Field', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
                const SizedBox(height: 10),
                const SearchHeader(hint: 'Bole, CMC, Sarbet...'),
                const SizedBox(height: 10),
                FilterChipsRow(labels: const ['Football', 'Basketball', 'Tennis'], selected: 'Football', onSelected: (_) {}),
                const SizedBox(height: 12),
                if (_loading)
                  const _LoadingMini()
                else if (_error)
                  _RetryBanner(onRetry: _load)
                else if (_fields.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('No fields available.', style: TextStyle(color: PFColors.muted))),
                  )
                else
                  ..._fields.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FieldCard(venue: f, onTap: () => Navigator.pushNamed(context, AppRoutes.fieldDetails, arguments: f.id)),
                  )),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 24,
          right: 20,
          child: FloatingActionButton(
            onPressed: () async {
              final added = await Navigator.pushNamed(context, AppRoutes.addField);
              if (added == true) _load();
            },
            backgroundColor: PFColors.accent,
            foregroundColor: PFColors.background,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ],
    );
  }
}

class _LeaguesTab extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const _LeaguesTab({required this.session, required this.repo});

  @override
  State<_LeaguesTab> createState() => _LeaguesTabState();
}

class _LeaguesTabState extends State<_LeaguesTab> {
  List<Map<String, dynamic>> _leagues = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    final leagues = await widget.repo.getLeagues(token);
    if (!mounted) return;
    setState(() {
      _leagues = leagues;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Center(
            child: Text('Join a League', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 12),
          PFCard(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 190,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        'assets/images/hero_volleyball.jpg',
                        fit: BoxFit.cover,
                        alignment: Alignment.centerRight,
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              PFColors.background.withValues(alpha: 0.90),
                              PFColors.background.withValues(alpha: 0.62),
                              PFColors.background.withValues(alpha: 0.12),
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 110, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Compete, climb, become a champion',
                            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.02),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Join leagues and compete with the best teams',
                            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const _LoadingMini()
          else ...[
            ..._leagues.map((l) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: LeagueCard(league: l, onTap: () => Navigator.pushNamed(context, AppRoutes.leagueDetails, arguments: {'id': l['id'] ?? 1, 'name': l['name'] ?? 'League'})),
            )),
            if (_leagues.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('No leagues yet. Create your first league below.', style: TextStyle(color: PFColors.muted)),
              ),
          ],
          const SizedBox(height: 6),
          PFButton(
            label: 'Create League',
            onTap: () async {
              final created = await Navigator.pushNamed(context, AppRoutes.createLeague);
              if (created == true) _load();
            },
          ),
        ],
      ),
    );
  }
}

class _ProfileTab extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const _ProfileTab({required this.session, required this.repo});

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _ratings = [];
  bool _loadingRatings = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    final userId = widget.session.user?['id'];
    if (token == null || userId == null) return;
    final result = await widget.repo.getProfileStats(token, userId as int);
    if (!mounted) return;
    setState(() => _stats = result['stats'] as Map<String, dynamic>?);
    _loadRatings();
  }

  Future<void> _loadRatings() async {
    final token = widget.session.token;
    final userId = widget.session.user?['id'];
    if (token == null || userId == null) return;
    setState(() => _loadingRatings = true);
    try {
      final result = await RankingService.getUserElo(token: token, userId: userId as int);
      if (!mounted) return;
      setState(() {
        _ratings = (result['ratings'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        _loadingRatings = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRatings = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.session.user ?? <String, dynamic>{};
    final metrics = {
      'Played': '${_stats?['matches_played'] ?? 0}',
      'Hosted': '${_stats?['matches_hosted'] ?? 0}',
      'Leagues': '${_stats?['leagues_joined'] ?? 0}',
    };
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              const Positioned(
                left: 0,
                child: SizedBox.shrink(),
              ),
              const Text('Profile', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              Positioned(
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.settings_rounded, color: PFColors.text),
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ProfileHeader(
            name: user['name']?.toString() ?? 'Player',
            location: (user['location']?.toString() ?? '').isNotEmpty ? user['location'].toString() : 'Addis Ababa, Ethiopia',
            profileImage: user['profile_image']?.toString(),
            metrics: metrics,
          ),
          const SizedBox(height: 12),
          if (_loadingRatings)
            const PFCard(child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: PFColors.accent))))
          else if (_ratings.isNotEmpty)
            PFCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Rankings', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  ...List.generate(_ratings.length, (i) {
                    final r = _ratings[i];
                    final sport = r['sport']?.toString() ?? '';
                    final elo = r['elo_rating'] ?? 1200;
                    final w = r['wins'] ?? 0;
                    final l = r['losses'] ?? 0;
                    final d = r['draws'] ?? 0;
                    final mp = r['matches_played'] ?? 0;
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        border: i < _ratings.length - 1 ? Border(bottom: BorderSide(color: PFColors.border.withValues(alpha: 0.3))) : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: PFColors.cardSoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(sport[0].toUpperCase() + sport.substring(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 12),
                          Text('$elo', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: PFColors.accent)),
                          const SizedBox(width: 8),
                          Text('ELO', style: const TextStyle(fontSize: 10, color: PFColors.muted)),
                          const Spacer(),
                          Text('$mp played  $w/$l/$d', style: const TextStyle(fontSize: 12, color: PFColors.muted)),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          const SizedBox(height: 12),
          PFCard(
            child: Column(
              children: [
                _ProfileTile(label: 'My Matches', onTap: () => Navigator.pushNamed(context, AppRoutes.exploreMatches)),
                _divider,
                _ProfileTile(label: 'My Bookings', onTap: () => Navigator.pushNamed(context, AppRoutes.myBookings)),
                _divider,
                _ProfileTile(label: 'My Teams', onTap: () => Navigator.pushNamed(context, AppRoutes.teamDetails, arguments: {'id': 1, 'name': 'Unity FC'})),
                _divider,
                _ProfileTile(label: 'My Leagues', onTap: () => Navigator.pushNamed(context, AppRoutes.leagues)),
                _divider,
                _ProfileTile(label: 'Notifications', onTap: () => Navigator.pushNamed(context, AppRoutes.notifications)),
                _divider,
                _ProfileTile(label: 'Payments', onTap: () => Navigator.pushNamed(context, AppRoutes.payments)),
                _divider,
                _ProfileTile(label: 'Settings', onTap: () => Navigator.pushNamed(context, AppRoutes.settings)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget get _divider => Divider(height: 1, color: PFColors.border.withValues(alpha: 0.25), indent: 0);

class _SectionHeader extends StatelessWidget {
  final String title;
  final String action;
  final VoidCallback onTap;
  const _SectionHeader({required this.title, required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        TextButton(onPressed: onTap, child: Text(action, style: const TextStyle(color: PFColors.accent))),
      ],
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ProfileTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: const Icon(Icons.chevron_right_rounded, color: PFColors.muted),
      onTap: onTap,
    );
  }
}

class _LoadingMini extends StatelessWidget {
  const _LoadingMini();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(child: CircularProgressIndicator(color: PFColors.accent)),
    );
  }
}
