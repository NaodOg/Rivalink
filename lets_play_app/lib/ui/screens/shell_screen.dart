import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/l10n.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../../core/data/services/venue_service.dart';
import '../../core/data/services/ranking_service.dart';
import '../../core/data/models/match.dart';
import '../widgets/bottom_tab_bar.dart';
import '../widgets/field_card.dart';
import '../widgets/filter_chips_row.dart';
import '../widgets/league_card.dart';
import '../widgets/match_card.dart';
import '../widgets/pf_avatar.dart';
import '../widgets/pf_badge.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_logo.dart';
import '../widgets/pf_rating_row.dart';
import '../widgets/pf_section_header.dart';
import '../widgets/pf_segmented.dart';
import '../widgets/pf_skeleton.dart';
import '../widgets/pf_sport_tile.dart';
import '../widgets/profile_header.dart';
import '../widgets/search_header.dart';
import '../widgets/notification_bell.dart';
import 'ranking_screen.dart';

class ShellScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  final int initialIndex;
  final bool startExploreVenues;
  const ShellScreen({
    super.key,
    required this.session,
    required this.repo,
    this.initialIndex = 0,
    this.startExploreVenues = false,
  });

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  late int _tab;
  final List<bool> _visited = List.generate(4, (_) => false);

  @override
  void initState() {
    super.initState();
    _tab = widget.initialIndex.clamp(0, 3);
    _visited[_tab] = true;
  }

  void _onTabChanged(int i) {
    if (i == _tab) return;
    setState(() {
      _visited[i] = true;
      _tab = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final repo = widget.repo;
    const empty = SizedBox.shrink();

    return Scaffold(
      backgroundColor: PFColors.background,
      body: AnimatedBuilder(
        animation: session,
        builder: (context, _) {
          final pages = [
            _visited[0] ? _HomeTab(session: session, repo: repo) : empty,
            _visited[1]
                ? _ExploreTab(session: session, repo: repo, startVenues: widget.startExploreVenues)
                : empty,
            _visited[2] ? _LeaguesTab(session: session, repo: repo) : empty,
            _visited[3] ? _ProfileTab(session: session, repo: repo) : empty,
          ];
          return IndexedStack(index: _tab, children: pages);
        },
      ),
      bottomNavigationBar: BottomTabBar(
        index: _tab,
        onChanged: _onTabChanged,
        onHost: () => Navigator.pushNamed(context, AppRoutes.hostMatch),
      ),
    );
  }
}

// ── Shared ──────────────────────────────────────────────────────────────────

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return L10n.t('home.morning');
  if (h < 17) return L10n.t('home.afternoon');
  return L10n.t('home.evening');
}

class _TopBar extends StatelessWidget {
  final SessionController session;
  final AppRepository repo;
  const _TopBar({required this.session, required this.repo});

  @override
  Widget build(BuildContext context) {
    final image = session.user?['profile_image']?.toString();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PFLogo(markSize: 32, wordSize: 20),
              const SizedBox(height: 4),
              Text('Addis Ababa, ET', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
        NotificationBell(session: session, repo: repo),
        GestureDetector(
          onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
          child: PFAvatar(name: session.user?['name']?.toString(), imageUrl: image, size: 40),
        ),
      ],
    );
  }
}

// ── Home ────────────────────────────────────────────────────────────────────

class _HomeTab extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const _HomeTab({required this.session, required this.repo});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  List<RivalinkMatch> _matches = [];
  List<Venue> _fields = [];
  List<Map<String, dynamic>> _leagues = [];
  List<RivalinkMatch> _forYou = [];
  bool _loading = true;
  bool _error = false;
  String _searchQuery = '';

  List<RivalinkMatch> get _filtered {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _matches;
    return _matches
        .where((m) =>
            m.title.toLowerCase().contains(q) ||
            m.location.toLowerCase().contains(q) ||
            m.sport.toLowerCase().contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() => _loading = true);
    setState(() => _error = false);
    try {
      final bundle = await widget.repo.getHomeBundle(token);
      if (!mounted) return;
      setState(() {
        _matches = List<RivalinkMatch>.from(bundle.upcomingMatches);
        _fields = List<Venue>.from(bundle.venues);
        _leagues = List<Map<String, dynamic>>.from(bundle.leagues);
        _forYou = bundle.forYou
            .map((e) => RivalinkMatch.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: PFColors.primary,
        backgroundColor: PFColors.surfaceRaised,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            _TopBar(session: widget.session, repo: widget.repo),
            const SizedBox(height: PFSpacing.xl),
            Text('${_greeting()}, ${_firstName()}',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(L10n.t('home.ready'),
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: PFSpacing.lg),
            SearchHeader(
              hint: L10n.t('home.search'),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: PFSpacing.lg),
            _CampaignHero(),
            if (_error)
              _ErrorBlock(onRetry: _load)
            else ...[
              if (_forYou.isNotEmpty) ...[
                const SizedBox(height: PFSpacing.xxl),
                PFSectionHeader(eyebrow: L10n.t('home.recommended'), title: L10n.t('home.for_you')),
                const SizedBox(height: PFSpacing.md),
                SizedBox(
                  height: 118,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: _forYou.length,
                    separatorBuilder: (_, __) => const SizedBox(width: PFSpacing.md),
                    itemBuilder: (_, i) {
                      final m = _forYou[i];
                      return SizedBox(
                        width: 280,
                        child: MatchCard(
                          match: m,
                          onTap: () => Navigator.pushNamed(context, AppRoutes.matchDetails, arguments: m.id),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: PFSpacing.xxl),
              PFSectionHeader(
                eyebrow: L10n.t('home.pickup'),
                title: L10n.t('home.your_matches'),
                action: L10n.t('common.view_all'),
                onAction: () => Navigator.pushNamed(context, AppRoutes.exploreMatches),
              ),
              const SizedBox(height: PFSpacing.md),
              if (_loading)
                const _RailSkeleton(height: 120)
              else if (_filtered.isEmpty)
                const _RailEmpty(
                  icon: Icons.sports_soccer_rounded,
                  text: 'No matches yet — be the first to host.',
                )
              else
                SizedBox(
                  height: 118,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(width: PFSpacing.md),
                    itemBuilder: (_, i) {
                      final m = _filtered[i];
                      return SizedBox(
                        width: 280,
                        child: MatchCard(
                          match: m,
                          onTap: () => Navigator.pushNamed(
                              context, AppRoutes.matchDetails, arguments: m.id),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: PFSpacing.xxl),
              PFSectionHeader(
                eyebrow: L10n.t('home.book_hour'),
                title: L10n.t('home.venues'),
                action: L10n.t('common.book'),
                onAction: () => Navigator.pushNamed(context, AppRoutes.bookField),
              ),
              const SizedBox(height: PFSpacing.md),
              if (_loading)
                const _RailSkeleton(height: 150)
              else if (_fields.isEmpty)
                const _RailEmpty(
                  icon: Icons.stadium_rounded,
                  text: 'No venues nearby yet.',
                )
              else
                SizedBox(
                  height: 190,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: _fields.length,
                    separatorBuilder: (_, __) => const SizedBox(width: PFSpacing.md),
                    itemBuilder: (_, i) {
                      final f = _fields[i];
                      return SizedBox(
                        width: 260,
                        child: FieldCard(
                          venue: f,
                          onTap: () => Navigator.pushNamed(
                              context, AppRoutes.fieldDetails, arguments: f.id),
                        ),
                      );
                    },
                  ),
                ),
              if (_leagues.isNotEmpty) ...[
                const SizedBox(height: PFSpacing.xxl),
                PFSectionHeader(
                  eyebrow: L10n.t('home.compete'),
                  title: L10n.t('home.leagues'),
                  action: L10n.t('common.see_all'),
                  onAction: () => Navigator.pushNamed(context, AppRoutes.leagues),
                ),
                const SizedBox(height: PFSpacing.md),
                ..._leagues.take(3).map((l) => Padding(
                      padding: const EdgeInsets.only(bottom: PFSpacing.md),
                      child: LeagueCard(
                        league: l,
                        onTap: () => Navigator.pushNamed(context, AppRoutes.leagueDetails,
                            arguments: {'id': l['id'] ?? 1, 'name': l['name'] ?? 'League'}),
                      ),
                    )),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _firstName() {
    final n = (widget.session.user?['name']?.toString() ?? '').trim();
    return n.isEmpty ? 'player' : n.split(' ').first;
  }
}

class _CampaignHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(PFRadius.xl),
      child: SizedBox(
        height: 200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/images/hero_soccer.jpg', fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    PFColors.scrim.withValues(alpha: 0.94),
                    PFColors.scrim.withValues(alpha: 0.55),
                    PFColors.scrim.withValues(alpha: 0.05),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(PFSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const PFBadge(label: 'LIVE NEAR YOU', color: PFColors.danger, solid: true),
                  const SizedBox(height: PFSpacing.md),
                  Text('Find your\nnext game.',
                      style: Theme.of(context).textTheme.displayMedium),
                  const SizedBox(height: PFSpacing.md),
                  PFButton(
                    label: 'Explore venues',
                    icon: Icons.arrow_forward_rounded,
                    expand: false,
                    dense: true,
                    onTap: () => Navigator.pushNamed(context, AppRoutes.bookField),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Explore ─────────────────────────────────────────────────────────────────

class _ExploreTab extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  final bool startVenues;
  const _ExploreTab({required this.session, required this.repo, this.startVenues = false});

  @override
  State<_ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<_ExploreTab> {
  late int _segment = widget.startVenues ? 1 : 0;
  List<RivalinkMatch> _matches = [];
  List<Venue> _fields = [];
  bool _loading = true;
  bool _error = false;
  String _searchQuery = '';
  String _sportFilter = 'All';

  static String? _sportCode(String label) {
    switch (label) {
      case 'Football':
        return 'soccer';
      case 'Basketball':
        return 'basketball';
      case 'Tennis':
        return 'tennis';
      default:
        return null;
    }
  }

  List<RivalinkMatch> get _filteredMatches {
    final q = _searchQuery.trim().toLowerCase();
    final code = _sportCode(_sportFilter);
    return _matches.where((m) {
      if (code != null && m.sport.toLowerCase() != code) return false;
      if (q.isEmpty) return true;
      return m.title.toLowerCase().contains(q) ||
          m.location.toLowerCase().contains(q) ||
          m.sport.toLowerCase().contains(q);
    }).toList();
  }

  List<Venue> get _filteredFields {
    final q = _searchQuery.trim().toLowerCase();
    final code = _sportCode(_sportFilter);
    return _fields.where((f) {
      if (code != null && !f.sports.any((s) => s.toLowerCase() == code)) return false;
      if (q.isEmpty) return true;
      return f.name.toLowerCase().contains(q) ||
          f.city.toLowerCase().contains(q) ||
          f.location.toLowerCase().contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final matches = token != null
          ? await widget.repo.getMatches(token, forceRefresh: true)
          : <RivalinkMatch>[];
      final fields = await widget.repo.getFields();
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _fields = fields;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Explore', style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: PFSpacing.lg),
                PFSegmented(
                  labels: const ['Matches', 'Venues'],
                  index: _segment,
                  onChanged: (i) => setState(() => _segment = i),
                ),
                const SizedBox(height: PFSpacing.md),
                SearchHeader(
                  hint: _segment == 1 ? 'Bole, CMC, Sarbet…' : '5v5 football near Bole',
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: PFColors.primary,
              backgroundColor: PFColors.surfaceRaised,
              child: _buildList(_segment == 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chips() => FilterChipsRow(
        labels: const ['All', 'Football', 'Basketball', 'Tennis'],
        selected: _sportFilter,
        onSelected: (v) => setState(() => _sportFilter = v),
      );

  Widget _buildList(bool isVenues) {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          _chips(),
          const SizedBox(height: PFSpacing.lg),
          const PFSkeletonCard(),
          const SizedBox(height: PFSpacing.md),
          const PFSkeletonCard(),
          const SizedBox(height: PFSpacing.md),
          const PFSkeletonCard(),
        ],
      );
    }
    final items = isVenues ? _filteredFields : _filteredMatches;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        _chips(),
        const SizedBox(height: PFSpacing.lg),
        if (_error)
          _ErrorBlock(onRetry: _load)
        else if (items.isEmpty)
          PFEmptyState(
            icon: isVenues ? Icons.stadium_rounded : Icons.search_off_rounded,
            title: isVenues ? 'No venues found' : 'No matches found',
            message: isVenues
                ? 'Try another area or sport.'
                : 'Try another search, or host the first one.',
            actionLabel: isVenues ? null : 'Host a match',
            onAction:
                isVenues ? null : () => Navigator.pushNamed(context, AppRoutes.hostMatch),
          )
        else
          for (int i = 0; i < items.length; i++) ...[
            if (isVenues)
              FieldCard(
                venue: _filteredFields[i],
                onTap: () => Navigator.pushNamed(context, AppRoutes.fieldDetails,
                    arguments: _filteredFields[i].id),
              )
            else
              MatchCard(
                match: _filteredMatches[i],
                onTap: () => Navigator.pushNamed(context, AppRoutes.matchDetails,
                    arguments: _filteredMatches[i].id),
              ),
            if (i < items.length - 1) const SizedBox(height: PFSpacing.md),
          ],
      ],
    );
  }
}

// ── Leagues ─────────────────────────────────────────────────────────────────

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
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final leagues = await widget.repo.getLeagues(token);
      if (!mounted) return;
      setState(() {
        _leagues = leagues;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: PFColors.primary,
        backgroundColor: PFColors.surfaceRaised,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text('Leagues', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 4),
            Text('Compete, climb, become a champion.',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: PFSpacing.lg),
            PFCard(
              raised: true,
              child: Row(
                children: [
                  const PFSportTile(sport: 'cricket', size: 52),
                  const SizedBox(width: PFSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Start a league',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text('Premium · all members',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  PFButton(
                    label: 'Create',
                    dense: true,
                    expand: false,
                    onTap: () async {
                      final created = await Navigator.pushNamed(context, AppRoutes.createLeague);
                      if (created == true) _load();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: PFSpacing.xxl),
            PFSectionHeader(eyebrow: 'Discover', title: 'All leagues'),
            const SizedBox(height: PFSpacing.md),
            if (_loading) ...[
              const PFSkeletonCard(height: 88),
              const SizedBox(height: PFSpacing.md),
              const PFSkeletonCard(height: 88),
            ] else if (_error)
              _ErrorBlock(onRetry: _load)
            else if (_leagues.isEmpty)
              const PFEmptyState(
                icon: Icons.emoji_events_rounded,
                title: 'No leagues yet',
                message: 'Create one and invite the best teams in Addis.',
              )
            else
              ..._leagues.map((l) => Padding(
                    padding: const EdgeInsets.only(bottom: PFSpacing.md),
                    child: LeagueCard(
                      league: l,
                      onTap: () => Navigator.pushNamed(context, AppRoutes.leagueDetails,
                          arguments: {'id': l['id'] ?? 1, 'name': l['name'] ?? 'League'}),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

// ── Profile ─────────────────────────────────────────────────────────────────

class _ProfileTab extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const _ProfileTab({required this.session, required this.repo});

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _userInfo;
  Map<String, dynamic>? _social;
  List<Map<String, dynamic>> _ratings = [];
  List<String> _form = [];
  bool _verified = false;
  bool _loading = true;
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
    setState(() => _loading = true);
    final result = await widget.repo.getProfileStats(token, userId as int);
    if (!mounted) return;
    setState(() {
      _stats = result['stats'] as Map<String, dynamic>?;
      _userInfo = result['user'] as Map<String, dynamic>?;
      _loading = false;
    });
    final social = await widget.repo.getSocialMe(token);
    if (!mounted) return;
    setState(() => _social = social);
    final phone = await widget.repo.getPhoneStatus(token);
    if (!mounted) return;
    setState(() => _verified = phone['phone_verified'] == true);
    final form = await widget.repo.getUserForm(token, userId as int);
    if (!mounted) return;
    setState(() => _form = form);
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
      setState(() {
        _loadingRatings = false;
        _ratings = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.session.user ?? <String, dynamic>{};
    final isPremium = user['is_premium'] == true;
    final favSports = (user['favorite_sports'] as List?)?.cast<String>() ?? const <String>[];
    final bio = user['bio']?.toString() ?? '';
    final joinedYear = _yearOf(_userInfo?['joined']?.toString());

    int bestElo = 1200;
    for (final r in _ratings) {
      final e = (r['elo_rating'] ?? 1200) as int;
      if (e > bestElo) bestElo = e;
    }
    final tier = pfEloTier(bestElo);

    final played = (_stats?['matches_played'] ?? 0) as int;
    final won = (_stats?['matches_won'] ?? 0) as int;
    final winPct = played > 0 ? (won / played * 100).round() : 0;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: PFColors.primary,
        backgroundColor: PFColors.surfaceRaised,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Profile', style: Theme.of(context).textTheme.displaySmall),
                ),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_rounded, color: PFColors.text),
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
                ),
              ],
            ),
            const SizedBox(height: PFSpacing.lg),
            ProfileHeader(
              name: user['name']?.toString() ?? 'Player',
              location: (user['location']?.toString() ?? '').isNotEmpty
                  ? user['location'].toString()
                  : 'Addis Ababa, Ethiopia',
              profileImage: user['profile_image']?.toString(),
              isPremium: isPremium,
              verified: _verified,
              favoriteSports: favSports,
              bio: bio,
              joinedYear: joinedYear,
              tierLabel: tier.label,
              tierColor: tier.color,
              onEditAvatar: () => Navigator.pushNamed(context, AppRoutes.editProfile),
            ),
            const SizedBox(height: PFSpacing.lg),
            _statCard(played, won, winPct),
            const SizedBox(height: PFSpacing.lg),
            _socialCard(),
            const SizedBox(height: PFSpacing.xxl),
            PFSectionHeader(
              eyebrow: 'Elo by sport',
              title: 'Your rating',
              action: 'Leaderboard',
              onAction: () => Navigator.pushNamed(context, AppRoutes.rankings),
            ),
            const SizedBox(height: PFSpacing.md),
            _ratingsCard(),
            const SizedBox(height: PFSpacing.xxl),
            _premiumCard(isPremium),
            const SizedBox(height: PFSpacing.xxl),
            _menuGroup('Activity', [
              _MenuTile(icon: PFIcons.matches, label: 'My matches',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.exploreMatches)),
              _MenuTile(icon: PFIcons.booking, label: 'My bookings',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.myBookings)),
              _MenuTile(icon: PFIcons.teams, label: 'My teams',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.myTeams)),
            ]),
            _menuGroup('Social', [
              _MenuTile(icon: PFIcons.users, label: 'Friends',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.friends)),
            ]),
            _menuGroup('Hosting', [
              _MenuTile(icon: PFIcons.venue, label: 'My venues',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.myVenues)),
              _MenuTile(icon: PFIcons.referee, label: 'Referees',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.referees)),
              _MenuTile(icon: PFIcons.trophy, label: 'Tournaments',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.tournaments)),
            ]),
            _menuGroup('Account', [
              _MenuTile(icon: PFIcons.bell, label: 'Notifications',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.notifications)),
              _MenuTile(icon: PFIcons.crown, label: 'Rivalink Premium',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.subscription)),
              _MenuTile(icon: PFIcons.card, label: 'Payments',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.payments)),
              _MenuTile(icon: PFIcons.gear, label: 'Settings',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.settings)),
            ]),
            if ((_social?['referral_code']?.toString() ?? '').isNotEmpty) _referralCard(),
          ],
        ),
      ),
    );
  }

  String? _yearOf(String? iso) {
    if (iso == null) return null;
    return DateTime.tryParse(iso)?.year.toString();
  }

  Widget _statCard(int played, int won, int winPct) {
    return PFCard(
      child: Column(
        children: [
          Row(
            children: [
              _stat('PLAYED', '$played'),
              _vdiv(),
              _stat('WON', '$won', primary: true),
              _vdiv(),
              _stat('WIN %', '$winPct%'),
            ],
          ),
          if (_form.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: PFColors.hairline),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('FORM', style: Theme.of(context).textTheme.labelSmall),
                const Spacer(),
                ..._form.map(_formPill),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {bool primary = false}) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: PFType.number.copyWith(
                  fontSize: 22, color: primary ? PFColors.primary : PFColors.text)),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }

  Widget _vdiv() => Container(
        width: 1,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: PFColors.hairline,
      );

  Widget _formPill(String o) {
    Color c = PFColors.textSecondary;
    if (o == 'W') {
      c = PFColors.success;
    } else if (o == 'L') {
      c = PFColors.danger;
    }
    return Container(
      margin: const EdgeInsets.only(left: 6),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(7),
      ),
      alignment: Alignment.center,
      child: Text(o, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
    );
  }

  Widget _socialCard() {
    final following = _social?['following_count'] ?? 0;
    final followers = _social?['followers_count'] ?? 0;
    return PFCard(
      onTap: () => Navigator.pushNamed(context, AppRoutes.friends),
      child: Row(
        children: [
          _socialStat(PFIcons.follow, 'Following', '$following'),
          _vdiv(),
          _socialStat(PFIcons.users, 'Followers', '$followers'),
          const Spacer(),
          const Icon(Icons.chevron_right_rounded, color: PFColors.textTertiary),
        ],
      ),
    );
  }

  Widget _socialStat(IconData icon, String label, String value) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 18, color: PFColors.textSecondary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: PFType.number.copyWith(fontSize: 16)),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ratingsCard() {
    if (_loadingRatings) return const PFSkeletonCard(height: 92);
    if (_ratings.isEmpty) {
      return PFCard(
        child: Row(
          children: [
            const Icon(Icons.lock_outline_rounded, color: PFColors.textTertiary),
            const SizedBox(width: PFSpacing.md),
            Expanded(
              child: Text('Play premium matches to earn an Elo rating.',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      );
    }
    return PFCard(
      child: Column(
        children: [
          for (int i = 0; i < _ratings.length; i++) ...[
            PFRatingRow(
              sport: _ratings[i]['sport']?.toString() ?? '',
              elo: _ratings[i]['elo_rating'] ?? 1200,
              wins: _ratings[i]['wins'] ?? 0,
              losses: _ratings[i]['losses'] ?? 0,
              draws: _ratings[i]['draws'] ?? 0,
              played: _ratings[i]['matches_played'] ?? 0,
            ),
            if (i < _ratings.length - 1) const Divider(height: 20),
          ],
        ],
      ),
    );
  }

  Widget _premiumCard(bool isPremium) {
    return PFCard(
      raised: true,
      onTap: () => Navigator.pushNamed(context, AppRoutes.subscription),
      child: Row(
        children: [
          Icon(PFIcons.crown, color: PFColors.primary),
          const SizedBox(width: PFSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isPremium ? 'Rivalink Premium' : 'Go Premium',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  isPremium
                      ? 'Your premium is active'
                      : 'Unlimited hosting, teams & leagues',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          isPremium
              ? const PFBadge(label: 'ACTIVE', color: PFColors.primary)
              : const Icon(Icons.chevron_right_rounded, color: PFColors.textTertiary),
        ],
      ),
    );
  }

  Widget _menuGroup(String title, List<Widget> tiles) {
    final children = <Widget>[];
    for (int i = 0; i < tiles.length; i++) {
      children.add(tiles[i]);
      if (i < tiles.length - 1) children.add(const PFCardDivider());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        ),
        PFCard(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: children)),
        const SizedBox(height: PFSpacing.lg),
      ],
    );
  }

  Widget _referralCard() {
    return PFCard(
      raised: true,
      child: Row(
        children: [
          const Icon(Icons.card_giftcard_rounded, color: PFColors.primary),
          const SizedBox(width: PFSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Invite friends', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'Code ${_social!['referral_code']} · Br ${_social!['referral_credit'] ?? 0} earned',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          PFButton(
            label: 'Copy',
            dense: true,
            expand: false,
            onTap: () {
              Clipboard.setData(ClipboardData(
                  text: 'Join me on Rivalink! Use my code ${_social!['referral_code']} to get started.'));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invite copied to clipboard')));
            },
          ),
        ],
      ),
    );
  }
}

// ── Small shared bits ────────────────────────────────────────────────────────

class PFCardDivider extends StatelessWidget {
  const PFCardDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 52, color: PFColors.hairline);
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Icon(icon, color: PFColors.textSecondary, size: 21),
      title: Text(label, style: Theme.of(context).textTheme.titleSmall),
      trailing: const Icon(Icons.chevron_right_rounded, color: PFColors.textTertiary),
      onTap: onTap,
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorBlock({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return PFEmptyState(
      icon: Icons.cloud_off_rounded,
      title: 'Couldn\'t load',
      message: 'Check your connection and try again.',
      actionLabel: 'Retry',
      onAction: onRetry,
    );
  }
}

class _RailEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _RailEmpty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PFSpacing.lg),
      decoration: BoxDecoration(
        color: PFColors.surface,
        borderRadius: BorderRadius.circular(PFRadius.lg),
        border: Border.all(color: PFColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: PFColors.textTertiary, size: 22),
          const SizedBox(width: PFSpacing.md),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _RailSkeleton extends StatelessWidget {
  final double height;
  const _RailSkeleton({required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 2,
        separatorBuilder: (_, __) => const SizedBox(width: PFSpacing.md),
        itemBuilder: (_, __) => const PFSkeleton(width: 280, height: 118, radius: PFRadius.lg),
      ),
    );
  }
}
