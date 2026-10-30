import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/l10n.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/data/media_config.dart';
import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/data/services/venue_service.dart';
import '../../core/data/services/ranking_service.dart';
import '../../core/data/services/analytics_service.dart';
import '../../core/data/models/match.dart';
import '../widgets/bottom_tab_bar.dart';
import '../widgets/explore_match_card.dart';
import '../widgets/field_card.dart';
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
  final String? tierLabel;
  final Color? tierColor;
  const _TopBar({
    required this.session,
    required this.repo,
    this.tierLabel,
    this.tierColor,
  });

  @override
  Widget build(BuildContext context) {
    final image = session.user?['profile_image']?.toString();
    final rawLocation = session.user?['location']?.toString().trim() ?? '';
    final location = rawLocation.isEmpty ? 'Addis Ababa, ET' : rawLocation;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PFLogo(markSize: 32, wordSize: 20),
              const SizedBox(height: 4),
              Row(
                children: [
                  Flexible(
                    child: Text(location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall),
                  ),
                  if (tierLabel != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: tierColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text(tierLabel!,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: tierColor)),
                  ],
                ],
              ),
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
  ({String label, Color color})? _tier;
  Map<String, dynamic>? _engagement;
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

  Future<void> _load({bool forceRefresh = false}) async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() => _loading = true);
    setState(() => _error = false);
    try {
      final bundle = await widget.repo.getHomeBundle(token, forceRefresh: forceRefresh);
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
      _loadExtras();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  /// Elo tier + engagement status — loaded after the main bundle so the page
  /// renders immediately and these fill in a moment later.
  Future<void> _loadExtras() async {
    final token = widget.session.token;
    final userId = widget.session.user?['id'];
    if (token == null || userId is! int) return;
    try {
      final results = await Future.wait<dynamic>([
        RankingService.getUserElo(token: token, userId: userId),
        widget.repo.getEngagementStatus(token),
      ]);
      if (!mounted) return;
      final eloRes = results[0] as Map<String, dynamic>;
      final engagement = results[1] as Map<String, dynamic>;
      var best = 0;
      for (final r in (eloRes['ratings'] as List<dynamic>? ?? const [])) {
        final rating = (r as Map)['elo_rating'];
        if (rating is int && rating > best) best = rating;
      }
      setState(() {
        _tier = best > 0 ? pfEloTier(best) : null;
        _engagement = engagement;
      });
    } catch (_) {
      // Extras are best-effort; the page works without them.
    }
  }

  @override
  Widget build(BuildContext context) {
    final soon = _soonMatches();
    final soonIds =
        soon.length >= 2 ? soon.map((m) => m.id).toSet() : const <int>{};
    final forYouRail = _forYou.where((m) => !soonIds.contains(m.id)).toList();
    var matchesRail = _filtered.where((m) => !soonIds.contains(m.id)).toList();
    if (matchesRail.isEmpty) matchesRail = _filtered;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => _load(forceRefresh: true),
        color: PFColors.primary,
        backgroundColor: PFColors.surfaceRaised,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            _TopBar(
              session: widget.session,
              repo: widget.repo,
              tierLabel: _tier?.label,
              tierColor: _tier?.color,
            ),
            const SizedBox(height: PFSpacing.xl),
            Text('${_greeting()}, ${_firstName()}',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(
              _loading && _matches.isEmpty ? L10n.t('home.ready') : _readyLine(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: PFSpacing.lg),
            SearchHeader(
              hint: L10n.t('home.search'),
              analyticsScreen: 'Home',
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: PFSpacing.lg),
            const _QuickActionsRow(),
            const SizedBox(height: PFSpacing.lg),
            _SpotlightHero(
              matches: _matches,
              leagues: _leagues,
              onExploreVenues: () =>
                  Navigator.pushNamed(context, AppRoutes.bookField),
            ),
            if (_error)
              _ErrorBlock(onRetry: _load)
            else ...[
              _happeningSoonSection(soon),
              if (forYouRail.isNotEmpty) ...[
                const SizedBox(height: PFSpacing.xxl),
                _Reveal(
                  delayMs: 60,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PFSectionHeader(
                        eyebrow: L10n.t('home.recommended'),
                        title: L10n.t('home.for_you'),
                        accent: PFColors.secondary,
                      ),
                      const SizedBox(height: 6),
                      Text(_reasonLabel(),
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: PFSpacing.md),
                      SizedBox(
                        height: 132,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          itemCount: forYouRail.length,
                          separatorBuilder: (_, __) => const SizedBox(width: PFSpacing.md),
                          itemBuilder: (_, i) {
                            final m = forYouRail[i];
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
                    ],
                  ),
                ),
              ],
              const SizedBox(height: PFSpacing.xxl),
              _Reveal(
                delayMs: 120,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PFSectionHeader(
                      eyebrow: L10n.t('home.pickup'),
                      title: L10n.t('home.your_matches'),
                      action: L10n.t('common.view_all'),
                      onAction: () =>
                          Navigator.pushNamed(context, AppRoutes.exploreMatches),
                      accent: PFColors.primary,
                    ),
                    const SizedBox(height: PFSpacing.md),
                    if (_loading)
                      const _RailSkeleton(height: 120)
                    else if (_filtered.isEmpty)
                      _RailEmpty(
                        icon: Icons.sports_soccer_rounded,
                        text: 'No matches yet — be the first to host.',
                        actionLabel: 'Host a match',
                        onAction: () =>
                            Navigator.pushNamed(context, AppRoutes.hostMatch),
                      )
                    else
                      SizedBox(
                        height: 118,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          itemCount: matchesRail.length,
                          separatorBuilder: (_, __) => const SizedBox(width: PFSpacing.md),
                          itemBuilder: (_, i) {
                            final m = matchesRail[i];
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
                  ],
                ),
              ),
              const SizedBox(height: PFSpacing.xxl),
              _Reveal(
                delayMs: 180,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PFSectionHeader(
                      eyebrow: L10n.t('home.book_hour'),
                      title: L10n.t('home.venues'),
                      action: L10n.t('common.book'),
                      onAction: () => Navigator.pushNamed(context, AppRoutes.bookField),
                      accent: PFColors.success,
                    ),
                    const SizedBox(height: PFSpacing.md),
                    if (_loading)
                      const _RailSkeleton(height: 150)
                    else if (_fields.isEmpty)
                      _RailEmpty(
                        icon: Icons.stadium_rounded,
                        text: 'No venues nearby yet.',
                        actionLabel: 'Find a venue',
                        onAction: () =>
                            Navigator.pushNamed(context, AppRoutes.bookField),
                      )
                    else
                      SizedBox(
                        height: 150,
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
                  ],
                ),
              ),
              if (_leagues.isNotEmpty) ...[
                const SizedBox(height: PFSpacing.xxl),
                _Reveal(
                  delayMs: 240,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PFSectionHeader(
                        eyebrow: L10n.t('home.compete'),
                        title: L10n.t('home.leagues'),
                        action: L10n.t('common.see_all'),
                        onAction: () => Navigator.pushNamed(context, AppRoutes.leagues),
                        accent: PFColors.gold,
                      ),
                      const SizedBox(height: PFSpacing.md),
                      ..._leagues.take(3).map((l) => Padding(
                            padding: const EdgeInsets.only(bottom: PFSpacing.md),
                            child: LeagueCard(
                              league: l,
                              onTap: () => Navigator.pushNamed(
                                  context, AppRoutes.leagueDetails,
                                  arguments: {'id': l['id'] ?? 1, 'name': l['name'] ?? 'League'}),
                            ),
                          )),
                    ],
                  ),
                ),
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

  String _reasonLabel() {
    final favs =
        (widget.session.user?['favorite_sports'] as List?)?.cast<String>() ??
            const <String>[];
    if (favs.isNotEmpty && favs.first.trim().isNotEmpty) {
      return 'Because you play ${favs.first}';
    }
    return 'Picked for you from your activity';
  }

  String _readyLine() {
    // Personalized next-best-action from the retention engine.
    final action = _engagement?['next_action'];
    final streak = _engagement?['streak'];
    final streakWeeks = (streak is Map ? streak['weeks'] : 0) as int? ?? 0;
    final suffix = streakWeeks >= 2 ? ' · $streakWeeks-week streak' : '';

    if (action is Map &&
        action['headline'] != null &&
        action['type'] != 'host_match') {
      return '${action['headline']}$suffix';
    }

    final now = DateTime.now();
    final upcoming = _matches.where((m) => m.dateTime.isAfter(now)).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    if (upcoming.isNotEmpty) {
      final next = upcoming.first;
      final diff = next.dateTime.difference(now);
      if (diff.inHours < 24) {
        final countdown = diff.inHours >= 1
            ? '${diff.inHours}h ${diff.inMinutes % 60}m'
            : '${diff.inMinutes}m';
        if (next.isOrganizer) {
          return 'You\'re hosting "${next.title}" — kicks off in $countdown$suffix';
        }
        return '${next.title} kicks off in $countdown$suffix';
      }
      final today = upcoming
          .where((m) =>
              m.dateTime.year == now.year &&
              m.dateTime.month == now.month &&
              m.dateTime.day == now.day)
          .length;
      if (today > 0) {
        return today == 1
            ? '1 match near you kicks off today$suffix'
            : '$today matches near you kick off today$suffix';
      }
      final week =
          upcoming.where((m) => m.dateTime.difference(now).inDays < 7).length;
      if (week > 0) {
        return week == 1
            ? '1 match open near you this week$suffix'
            : '$week matches open near you this week$suffix';
      }
    }
    return streakWeeks >= 2
        ? 'You are on a $streakWeeks-week streak — keep it going'
        : 'No games yet — host one in 2 minutes';
  }

  List<RivalinkMatch> _soonMatches() {
    final now = DateTime.now();
    return _matches
        .where((m) =>
            !m.isFull &&
            m.dateTime.isAfter(now) &&
            m.dateTime.difference(now).inHours < 24)
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  Widget _happeningSoonSection(List<RivalinkMatch> soon) {
    if (soon.length < 2 || _loading) return const SizedBox.shrink();
    return _Reveal(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: PFSpacing.xxl),
          const PFSectionHeader(
            eyebrow: 'Starting soon',
            title: 'Happening within 24h',
            accent: PFColors.warning,
          ),
          const SizedBox(height: PFSpacing.md),
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: soon.length,
              separatorBuilder: (_, __) => const SizedBox(width: PFSpacing.md),
              itemBuilder: (_, i) {
                final m = soon[i];
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
        ],
      ),
    );
  }
}

class _SpotlightHero extends StatelessWidget {
  final List<RivalinkMatch> matches;
  final List<Map<String, dynamic>> leagues;
  final VoidCallback onExploreVenues;
  const _SpotlightHero({
    required this.matches,
    required this.leagues,
    required this.onExploreVenues,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcoming = matches.where((m) => m.dateTime.isAfter(now)).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    if (upcoming.isNotEmpty) {
      return _MatchSpotlight(match: upcoming.first);
    }
    final league = _closingLeague(now);
    if (league != null) {
      return _LeagueSpotlight(league: league);
    }
    return _EvergreenHero(onExploreVenues: onExploreVenues);
  }

  Map<String, dynamic>? _closingLeague(DateTime now) {
    final candidates = leagues.where((l) {
      final start = DateTime.tryParse(l['start_date']?.toString() ?? '');
      if (start == null) return false;
      final diff = start.difference(now);
      return !diff.isNegative && diff.inDays <= 3;
    }).toList()
      ..sort((a, b) => (a['start_date'] ?? '')
          .toString()
          .compareTo((b['start_date'] ?? '').toString()));
    return candidates.isNotEmpty ? candidates.first : null;
  }
}

class _MatchSpotlight extends StatelessWidget {
  final RivalinkMatch match;
  const _MatchSpotlight({required this.match});

  String _countdown() {
    final d = match.dateTime.difference(DateTime.now());
    if (d.isNegative) return 'STARTING';
    if (d.inHours >= 1) return 'IN ${d.inHours}H ${d.inMinutes % 60}M';
    return 'IN ${d.inMinutes}M';
  }

  @override
  Widget build(BuildContext context) {
    final color = PFSport.color(match.sport);
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
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    color.withValues(alpha: 0.50),
                    PFColors.scrim.withValues(alpha: 0.92),
                  ],
                ),
              ),
            ),
            Positioned(
              right: -16,
              bottom: -16,
              child: Icon(PFSport.icon(match.sport),
                  size: 170,
                  color: Colors.white.withValues(alpha: 0.08)),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    PFColors.scrim.withValues(alpha: 0.85),
                    PFColors.scrim.withValues(alpha: 0.15),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(PFSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PFBadge(
                    label: 'NEXT UP · ${_countdown()}',
                    color: PFColors.danger,
                    solid: true,
                  ),
                  const SizedBox(height: PFSpacing.md),
                  Text(match.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 6),
                  Text(
                    '${prettyDate(match.dateTime)} · ${match.location}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: PFSpacing.md),
                  PFButton(
                    label: 'View match',
                    icon: Icons.arrow_forward_rounded,
                    expand: false,
                    dense: true,
                    onTap: () => Navigator.pushNamed(
                        context, AppRoutes.matchDetails, arguments: match.id),
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

class _LeagueSpotlight extends StatelessWidget {
  final Map<String, dynamic> league;
  const _LeagueSpotlight({required this.league});

  @override
  Widget build(BuildContext context) {
    final name = league['name']?.toString() ?? 'League';
    final prize = league['prize']?.toString() ?? '';
    final format = league['format']?.toString() ?? '';
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
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    PFColors.gold.withValues(alpha: 0.40),
                    PFColors.scrim.withValues(alpha: 0.92),
                  ],
                ),
              ),
            ),
            Positioned(
              right: -16,
              bottom: -16,
              child: Icon(Icons.emoji_events_rounded,
                  size: 170, color: Colors.white.withValues(alpha: 0.08)),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    PFColors.scrim.withValues(alpha: 0.85),
                    PFColors.scrim.withValues(alpha: 0.15),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(PFSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const PFBadge(
                    label: 'REGISTRATION CLOSING',
                    color: PFColors.warning,
                    solid: true,
                  ),
                  const SizedBox(height: PFSpacing.md),
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 6),
                  Text(
                    prize.isNotEmpty
                        ? '$format · Prize $prize'
                        : (format.isNotEmpty ? format : 'Join before it starts'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: PFSpacing.md),
                  PFButton(
                    label: 'View league',
                    icon: Icons.arrow_forward_rounded,
                    expand: false,
                    dense: true,
                    onTap: () => Navigator.pushNamed(context, AppRoutes.leagueDetails,
                        arguments: {
                          'id': league['id'] ?? 1,
                          'name': name,
                        }),
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

class _EvergreenHero extends StatelessWidget {
  final VoidCallback onExploreVenues;
  const _EvergreenHero({required this.onExploreVenues});

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
                    onTap: onExploreVenues,
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

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _action(context, Icons.add_circle_outline_rounded, 'Host', PFColors.primary,
            () => Navigator.pushNamed(context, AppRoutes.hostMatch)),
        const SizedBox(width: PFSpacing.sm),
        _action(context, Icons.stadium_rounded, 'Book venue', PFColors.success,
            () => Navigator.pushNamed(context, AppRoutes.bookField)),
        const SizedBox(width: PFSpacing.sm),
        _action(context, Icons.leaderboard_rounded, 'Rankings', PFColors.warning,
            () => Navigator.pushNamed(context, AppRoutes.rankings)),
        const SizedBox(width: PFSpacing.sm),
        _action(context, Icons.sports_rounded, 'Referees', PFColors.secondary,
            () => Navigator.pushNamed(context, AppRoutes.referees)),
      ],
    );
  }

  Widget _action(BuildContext context, IconData icon, String label, Color color,
      VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: PFColors.surface,
            borderRadius: BorderRadius.circular(PFRadius.md),
            border: Border.all(color: PFColors.border),
          ),
          child: Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w700, color: PFColors.text)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Reveal extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const _Reveal({required this.child, this.delayMs = 0});

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void initState() {
    super.initState();
    if (widget.delayMs <= 0) {
      _c.forward();
    } else {
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
            .animate(curved),
        child: widget.child,
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
  int _searchEpoch = 0;

  static const List<String> _sportLabels = ['All', 'Football', 'Basketball', 'Tennis'];

  bool get _filtersActive =>
      _searchQuery.trim().isNotEmpty || _sportFilter != 'All';

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _sportFilter = 'All';
      _searchEpoch++;
    });
  }

  String _filtersActiveLabel() {
    final parts = <String>[];
    if (_sportFilter != 'All') parts.add(_sportFilter);
    final q = _searchQuery.trim();
    if (q.isNotEmpty) parts.add('"$q"');
    return parts.join(' · ');
  }

  static String _dateBucket(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = day.difference(today).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff < 7 &&
        (dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday)) {
      return 'This weekend';
    }
    if (diff < 7) return 'This week';
    return 'Later';
  }

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

  RivalinkMatch? get _featuredMatch {
    final list = _filteredMatches;
    if (list.isEmpty) return null;
    for (final match in list) {
      if (match.spotsLeft > 0) return match;
    }
    return list.first;
  }

  int get _openSpots {
    var total = 0;
    for (final match in _filteredMatches) {
      if (match.spotsLeft > 0) total += match.spotsLeft;
    }
    return total;
  }

  int get _verifiedVenues => _filteredFields
      .where((venue) => venue.verificationStatus == 'verified')
      .length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final token = widget.session.token;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final matches = token != null
          ? await widget.repo.getMatches(token, forceRefresh: forceRefresh)
          : <RivalinkMatch>[];
      final fields = await widget.repo.getFields(forceRefresh: forceRefresh);
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
    final glow = _sportFilter == 'All'
        ? PFColors.primary
        : PFSport.color(_sportCode(_sportFilter) ?? 'other');
    return Stack(
      children: [
        Positioned(
          top: -110,
          left: -80,
          right: -80,
          child: IgnorePointer(
            child: Container(
              height: 300,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.1, -0.4),
                  radius: 0.9,
                  colors: [
                    glow.withValues(alpha: 0.18),
                    glow.withValues(alpha: 0.04),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Explore',
                        style: Theme.of(context).textTheme.displaySmall),
                    const SizedBox(height: 4),
                    Text(
                      _segment == 1
                          ? 'Find a pitch. Book the slot.'
                          : 'Find a game. Fill a pitch.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: PFSpacing.lg),
                    PFSegmented(
                      labels: [
                        _matches.isEmpty
                            ? 'Matches'
                            : 'Matches (${_matches.length})',
                        _fields.isEmpty
                            ? 'Venues'
                            : 'Venues (${_fields.length})',
                      ],
                      index: _segment,
                      onChanged: (i) => setState(() => _segment = i),
                    ),
                    const SizedBox(height: PFSpacing.md),
                    SearchHeader(
                      key: ValueKey('explore-search-$_searchEpoch'),
                      hint: _segment == 1
                          ? 'Bole, CMC, Sarbet…'
                          : '5v5 football near Bole',
                      analyticsScreen: 'Explore',
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _load(forceRefresh: true),
                  color: PFColors.primary,
                  backgroundColor: PFColors.surfaceRaised,
                  child: _buildList(_segment == 1),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chips() => SizedBox(
        height: 42,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _sportLabels.length,
          separatorBuilder: (_, __) => const SizedBox(width: PFSpacing.sm),
          itemBuilder: (_, i) {
            final label = _sportLabels[i];
            final active = _sportFilter == label;
            final code = _sportCode(label);
            final color =
                label == 'All' ? PFColors.primary : PFSport.color(code ?? 'other');
            final icon = label == 'All'
                ? Icons.grid_view_rounded
                : PFSport.icon(code ?? 'other');
            return Center(
              child: GestureDetector(
                onTap: () {
                  setState(() => _sportFilter = label);
                  AnalyticsService.event('filter_applied', {
                    'filter': label,
                    'screen': 'Explore',
                  });
                },
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: active ? color.withValues(alpha: 0.16) : PFColors.surface,
                    borderRadius: BorderRadius.circular(PFRadius.pill),
                    border: Border.all(
                      color: active ? color : PFColors.border,
                      width: active ? 1.2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          size: 15,
                          color: active ? color : PFColors.textTertiary),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: active ? color : PFColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );

  List<Widget> _matchAgenda({int? excludeId}) {
    const order = ['Today', 'Tomorrow', 'This weekend', 'This week', 'Later'];
    final groups = <String, List<RivalinkMatch>>{};
    for (final m in _filteredMatches) {
      if (m.id == excludeId) continue;
      groups.putIfAbsent(_dateBucket(m.dateTime), () => []).add(m);
    }
    final widgets = <Widget>[];
    for (final key in order) {
      final list = groups[key];
      if (list == null || list.isEmpty) continue;
      final accent = switch (key) {
        'Today' => PFColors.primary,
        'Tomorrow' => PFColors.secondary,
        'This weekend' => PFColors.gold,
        _ => PFColors.textTertiary,
      };
      widgets.add(Padding(
        padding: EdgeInsets.only(
            top: widgets.isEmpty ? 0 : PFSpacing.xl, bottom: PFSpacing.md),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(PFRadius.sm),
                border: Border.all(color: accent.withValues(alpha: 0.3)),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.calendar_today_rounded,
                  size: 14, color: accent),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  key.toUpperCase(),
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: accent, letterSpacing: 1.2),
                ),
                Text(
                  '${list.length} ${list.length == 1 ? 'match' : 'matches'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 1,
                color: accent.withValues(alpha: 0.18),
              ),
            ),
          ],
        ),
      ));
      for (var i = 0; i < list.length; i++) {
        final m = list[i];
        widgets.add(ExploreMatchCard(
          match: m,
          onTap: () => Navigator.pushNamed(context, AppRoutes.matchDetails,
              arguments: m.id),
        ));
        if (i < list.length - 1) {
          widgets.add(const SizedBox(height: PFSpacing.md));
        }
      }
    }
    return widgets;
  }

  List<Widget> _venueSections() {
    final venues = _filteredFields;
    final featured = venues.firstWhere(
      (v) => v.verificationStatus == 'verified',
      orElse: () => venues.first,
    );
    final grid = venues.where((v) => v.id != featured.id).toList();
    return [
      _FeaturedVenueCard(
        venue: featured,
        onTap: () => Navigator.pushNamed(context, AppRoutes.fieldDetails,
            arguments: featured.id),
      ),
      if (grid.isNotEmpty) ...[
        const SizedBox(height: PFSpacing.lg),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: PFSpacing.md,
          crossAxisSpacing: PFSpacing.md,
          childAspectRatio: 0.82,
          children: [
            for (final v in grid)
              _VenueGridCard(
                venue: v,
                onTap: () => Navigator.pushNamed(
                    context, AppRoutes.fieldDetails, arguments: v.id),
              ),
          ],
        ),
      ],
    ];
  }

  Widget _buildList(bool isVenues) {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: const [
          PFSkeletonCard(),
          SizedBox(height: PFSpacing.md),
          PFSkeletonCard(),
          SizedBox(height: PFSpacing.md),
          PFSkeletonCard(),
        ],
      );
    }
    final items = isVenues ? _filteredFields : _filteredMatches;
    final countLabel = isVenues
        ? '${items.length} ${items.length == 1 ? 'venue' : 'venues'}'
        : '${items.length} ${items.length == 1 ? 'match' : 'matches'}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        _chips(),
        const SizedBox(height: PFSpacing.md),
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: isVenues ? PFColors.gold : PFColors.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                _filtersActive
                    ? '$countLabel · ${_filtersActiveLabel()}'
                    : countLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            Text(
              isVenues
                  ? '$_verifiedVenues verified'
                  : '$_openSpots spots open',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isVenues ? PFColors.gold : PFColors.success,
                  ),
            ),
          ],
        ),
        const SizedBox(height: PFSpacing.lg),
        if (_error)
          _ErrorBlock(onRetry: _load)
        else if (items.isEmpty)
          PFEmptyState(
            icon: isVenues ? Icons.stadium_rounded : Icons.search_off_rounded,
            title: isVenues ? 'No venues found' : 'No matches found',
            message: _filtersActive
                ? 'Nothing matches these filters.'
                : (isVenues
                    ? 'Try another area or sport.'
                    : 'Try another search, or host the first one.'),
            actionLabel: _filtersActive
                ? 'Clear filters'
                : (isVenues ? null : 'Host a match'),
            onAction: _filtersActive
                ? _clearFilters
                : (isVenues
                    ? null
                    : () => Navigator.pushNamed(context, AppRoutes.hostMatch)),
          )
        else if (isVenues)
          ..._venueSections()
        else ...[
          if (_featuredMatch != null) ...[
            ExploreFeaturedMatchCard(
              match: _featuredMatch!,
              onTap: () => Navigator.pushNamed(
                  context, AppRoutes.matchDetails,
                  arguments: _featuredMatch!.id),
            ),
            const SizedBox(height: PFSpacing.xxl),
          ],
          ..._matchAgenda(excludeId: _featuredMatch?.id),
        ],
      ],
    );
  }
}

class _FeaturedVenueCard extends StatelessWidget {
  final Venue venue;
  final VoidCallback? onTap;
  const _FeaturedVenueCard({required this.venue, this.onTap});

  @override
  Widget build(BuildContext context) {
    final img = MediaConfig.resolve(venue.primaryImage);
    final sport = venue.sports.isNotEmpty ? venue.sports.first : 'other';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: PFColors.surface,
          borderRadius: BorderRadius.circular(PFRadius.lg),
          border: Border.all(color: PFColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (img != null)
              CachedNetworkImage(
                imageUrl: img,
                fit: BoxFit.cover,
                placeholder: (_, __) => _SportBanner(sport: sport),
                errorWidget: (_, __, ___) => _SportBanner(sport: sport),
              )
            else
              _SportBanner(sport: sport),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    PFColors.scrim.withValues(alpha: 0.92),
                    PFColors.scrim.withValues(alpha: 0.1),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: PFBadge(label: 'FEATURED', color: PFColors.gold, solid: true),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(venue.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('Br ${venue.slotPrice.toStringAsFixed(0)}/2h',
                          style: const TextStyle(
                              color: PFColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      if (venue.city.isNotEmpty)
                        Text(venue.city,
                            style: Theme.of(context).textTheme.bodySmall),
                      const Spacer(),
                      if (venue.averageRating > 0) ...[
                        const Icon(Icons.star_rounded,
                            size: 14, color: PFColors.gold),
                        const SizedBox(width: 2),
                        Text(venue.averageRating.toStringAsFixed(1),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: PFColors.text)),
                      ],
                    ],
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

class _SportBanner extends StatelessWidget {
  final String sport;
  const _SportBanner({required this.sport});

  @override
  Widget build(BuildContext context) {
    final color = PFSport.color(sport);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.45), PFColors.surface],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(PFSport.icon(sport),
          size: 36, color: color.withValues(alpha: 0.8)),
    );
  }
}

class _VenueGridCard extends StatelessWidget {
  final Venue venue;
  final VoidCallback? onTap;
  const _VenueGridCard({required this.venue, this.onTap});

  @override
  Widget build(BuildContext context) {
    final img = MediaConfig.resolve(venue.primaryImage);
    final sport = venue.sports.isNotEmpty ? venue.sports.first : 'other';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: PFColors.surface,
          borderRadius: BorderRadius.circular(PFRadius.lg),
          border: Border.all(color: PFColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 96,
              width: double.infinity,
              child: img != null
                  ? CachedNetworkImage(
                      imageUrl: img,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _SportBanner(sport: sport),
                      errorWidget: (_, __, ___) => _SportBanner(sport: sport),
                    )
                  : _SportBanner(sport: sport),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(venue.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(venue.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                    const Spacer(),
                    Row(
                      children: [
                        Text('Br ${venue.slotPrice.toStringAsFixed(0)}/2h',
                            style: const TextStyle(
                                color: PFColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                        const Spacer(),
                        if (venue.verificationStatus == 'verified')
                          const Icon(Icons.verified_rounded,
                              size: 13, color: PFColors.success),
                        if (venue.averageRating > 0) ...[
                          const SizedBox(width: 3),
                          const Icon(Icons.star_rounded,
                              size: 13, color: PFColors.gold),
                          const SizedBox(width: 2),
                          Text(venue.averageRating.toStringAsFixed(1),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: PFColors.text)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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

  Future<void> _load({bool forceRefresh = false}) async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final leagues = await widget.repo.getLeagues(token, forceRefresh: forceRefresh);
      int prio(Map<String, dynamic> l) =>
          switch (l['status']?.toString() ?? 'registration') {
            'live' => 0,
            'registration' => 1,
            _ => 2,
          };
      leagues.sort((a, b) {
        final byStatus = prio(a).compareTo(prio(b));
        if (byStatus != 0) return byStatus;
        return (a['start_date']?.toString() ?? '')
            .compareTo(b['start_date']?.toString() ?? '');
      });
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
        onRefresh: () => _load(forceRefresh: true),
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
  bool _loadingRatings = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final token = widget.session.token;
    final userId = widget.session.user?['id'];
    if (token == null || userId == null) return;
    try {
      final result = await widget.repo.getProfileStats(token, userId as int, forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _stats = result['stats'] as Map<String, dynamic>?;
        _userInfo = result['user'] as Map<String, dynamic>?;
      });
      final social = await widget.repo.getSocialMe(token);
      if (!mounted) return;
      setState(() => _social = social);
      final phone = await widget.repo.getPhoneStatus(token);
      if (!mounted) return;
      setState(() => _verified = phone['phone_verified'] == true);
      final form = await widget.repo.getUserForm(token, userId);
      if (!mounted) return;
      setState(() => _form = form);
      await _loadRatings();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stats = null;
        _userInfo = null;
        _social = null;
        _form = [];
        _ratings = [];
        _verified = false;
        _loadingRatings = false;
      });
    }
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
        onRefresh: () => _load(forceRefresh: true),
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
              followingCount: (_social?['following_count'] ?? 0) as int,
              followersCount: (_social?['followers_count'] ?? 0) as int,
              onSocialTap: () => Navigator.pushNamed(context, AppRoutes.friends),
              onEditAvatar: () => Navigator.pushNamed(context, AppRoutes.editProfile),
            ),
            const SizedBox(height: PFSpacing.lg),
            _statCard(played, won, winPct),
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
            _menuGroup('Activity', tint: PFColors.primary, [
              _MenuTile(
                  icon: PFIcons.matches,
                  label: 'My matches',
                  tint: PFColors.primary,
                  trailingText: ((_stats?['matches_played'] ?? 0) as int) > 0
                      ? '${_stats!['matches_played']}'
                      : null,
                  onTap: () => Navigator.pushNamed(context, AppRoutes.exploreMatches)),
              _MenuTile(
                  icon: PFIcons.booking,
                  label: 'My bookings',
                  tint: PFColors.primary,
                  onTap: () => Navigator.pushNamed(context, AppRoutes.myBookings)),
              _MenuTile(
                  icon: PFIcons.teams,
                  label: 'My teams',
                  tint: PFColors.primary,
                  trailingText: ((_stats?['teams_member'] ?? 0) as int) > 0
                      ? '${_stats!['teams_member']}'
                      : null,
                  onTap: () => Navigator.pushNamed(context, AppRoutes.myTeams)),
            ]),
            _menuGroup('Social', tint: const Color(0xFFB07CFF), [
              _MenuTile(
                  icon: PFIcons.users,
                  label: 'Friends',
                  tint: const Color(0xFFB07CFF),
                  onTap: () => Navigator.pushNamed(context, AppRoutes.friends)),
            ]),
            _menuGroup('Hosting', tint: PFColors.success, [
              _MenuTile(
                  icon: PFIcons.venue,
                  label: 'My venues',
                  tint: PFColors.success,
                  onTap: () => Navigator.pushNamed(context, AppRoutes.myVenues)),
              _MenuTile(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Host earnings',
                  tint: PFColors.success,
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.hostEarnings)),
              _MenuTile(
                  icon: PFIcons.referee,
                  label: 'Referees',
                  tint: PFColors.success,
                  onTap: () => Navigator.pushNamed(context, AppRoutes.referees)),
              _MenuTile(
                  icon: PFIcons.trophy,
                  label: 'Tournaments',
                  tint: PFColors.success,
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.tournaments)),
            ]),
            _menuGroup('Account', tint: PFColors.textSecondary, [
              _MenuTile(
                  icon: PFIcons.bell,
                  label: 'Notifications',
                  tint: PFColors.textSecondary,
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.notifications)),
              _MenuTile(
                  icon: PFIcons.crown,
                  label: 'Victiqo Premium',
                  tint: PFColors.textSecondary,
                  onTap: () => Navigator.pushNamed(context, AppRoutes.subscription)),
              _MenuTile(
                  icon: PFIcons.card,
                  label: 'Payments',
                  tint: PFColors.textSecondary,
                  onTap: () => Navigator.pushNamed(context, AppRoutes.payments)),
              _MenuTile(
                  icon: Icons.savings_outlined,
                  label: 'Credits',
                  tint: PFColors.textSecondary,
                  onTap: () => Navigator.pushNamed(context, AppRoutes.credits)),
              _MenuTile(
                  icon: PFIcons.gear,
                  label: 'Settings',
                  tint: PFColors.textSecondary,
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
              _winArc(winPct),
              _vdiv(),
              _stat('PLAYED', '$played'),
              _vdiv(),
              _stat('WON', '$won', primary: true),
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

  Widget _winArc(int pct) {
    final value = (pct.clamp(0, 100)) / 100;
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 6,
              strokeCap: StrokeCap.round,
              backgroundColor: PFColors.surfaceHigh,
              valueColor: const AlwaysStoppedAnimation(PFColors.primary),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$pct%',
                  style: PFType.number.copyWith(fontSize: 15, color: PFColors.text)),
              const Text('WIN',
                  style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: PFColors.textTertiary)),
            ],
          ),
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
                Text(isPremium ? 'Victiqo Premium' : 'Go Premium',
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

  Widget _menuGroup(String title, List<Widget> tiles, {Color? tint}) {
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
          child: Row(
            children: [
              if (tint != null) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(title.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
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
                  text: 'Join me on Victiqo! Use my code ${_social!['referral_code']} to get started.'));
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
  final Color? tint;
  final String? trailingText;
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
    this.trailingText,
  });

  @override
  Widget build(BuildContext context) {
    final color = tint ?? PFColors.textSecondary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(label, style: Theme.of(context).textTheme.titleSmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null) ...[
            Text(trailingText!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: PFColors.textSecondary)),
            const SizedBox(width: 6),
          ],
          const Icon(Icons.chevron_right_rounded, color: PFColors.textTertiary),
        ],
      ),
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
  final String? actionLabel;
  final VoidCallback? onAction;
  const _RailEmpty({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PFSpacing.lg),
      decoration: BoxDecoration(
        color: PFColors.surface,
        borderRadius: BorderRadius.circular(PFRadius.lg),
        border: Border.all(color: PFColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: PFColors.textTertiary, size: 22),
              const SizedBox(width: PFSpacing.md),
              Expanded(
                child: Text(text, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: PFSpacing.md),
            PFButton(
              label: actionLabel!,
              expand: false,
              dense: true,
              onTap: onAction,
            ),
          ],
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
