import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../../core/utils/formatters.dart';
import '../widgets/pf_badge.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_section_header.dart';
import '../widgets/pf_sport_tile.dart';

class LeagueDetailsScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  final int leagueId;
  final String leagueName;
  const LeagueDetailsScreen({
    super.key,
    required this.session,
    required this.repo,
    required this.leagueId,
    required this.leagueName,
  });

  @override
  State<LeagueDetailsScreen> createState() => _LeagueDetailsScreenState();
}

class _LeagueDetailsScreenState extends State<LeagueDetailsScreen> {
  Map<String, dynamic>? _league;
  List<dynamic> _standings = [];
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
      final result = await widget.repo.getLeagueDetails(token, widget.leagueId);
      if (!mounted) return;
      setState(() {
        _league = result['league'] as Map<String, dynamic>?;
        _standings = List<dynamic>.from(result['standings'] ?? []);
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

  Future<void> _join() async {
    final token = widget.session.token;
    if (token == null) return;
    final teams = await widget.repo.getMyTeams(token);
    if (!mounted) return;
    if (teams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need a team first')),
      );
      return;
    }
    int? teamId;
    if (teams.length == 1) {
      teamId = teams[0]['id'] as int;
    } else {
      teamId = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          backgroundColor: PFColors.surfaceRaised,
          title: const Text('Choose a team'),
          children: teams
              .map<Widget>((t) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, t['id'] as int),
                    child: Text(t['name']?.toString() ?? 'Team',
                        style: const TextStyle(fontSize: 15)),
                  ))
              .toList(),
        ),
      );
    }
    if (teamId == null) return;
    try {
      final res = await widget.repo.joinLeague(token, widget.leagueId, teamId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((res['message'] ?? res['error'] ?? '').toString())));
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed to join league')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PFColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.leagueName),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PFColors.primary))
          : _error
              ? Center(
                  child: PFEmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: "Couldn't load league",
                    actionLabel: 'Retry',
                    onAction: _load,
                  ),
                )
              : _league == null
                  ? const Center(
                      child: PFEmptyState(
                          icon: Icons.search_off_rounded, title: 'League not found'))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        _hero(),
                        const SizedBox(height: PFSpacing.lg),
                        _info(),
                        const SizedBox(height: PFSpacing.xxl),
                        PFSectionHeader(
                          eyebrow: 'Table',
                          title: 'Standings',
                          trailing: PFBadge(
                            label: '${_standings.length} ${_standings.length == 1 ? 'team' : 'teams'}',
                          ),
                        ),
                        const SizedBox(height: PFSpacing.md),
                        if (_standings.isEmpty)
                          const PFEmptyState(
                            icon: Icons.emoji_events_rounded,
                            title: 'No teams yet',
                            message: 'Be the first to join this league.',
                          )
                        else
                          _standingsTable(),
                      ],
                    ),
      bottomNavigationBar: _league != null ? _bottomBar() : null,
    );
  }

  Widget _hero() {
    final sport = _league?['sport']?.toString() ?? 'sport';
    final name = _league?['name']?.toString() ?? widget.leagueName;
    final format = _league?['format']?.toString() ?? 'League';
    final startDate = _league?['start_date']?.toString() ?? '';
    final current = _league?['current_teams'] ?? 0;
    final max = _league?['max_teams'] ?? 8;
    final color = PFSport.color(sport);

    return PFCard(
      padding: EdgeInsets.zero,
      radius: PFRadius.xl,
      child: Container(
        padding: const EdgeInsets.all(PFSpacing.xl),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: 0.20), PFColors.surface],
            stops: const [0.0, 0.7],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PFSportTile(sport: sport, size: 44),
                const Spacer(),
                PFBadge(label: '$current / $max teams', color: color),
              ],
            ),
            const SizedBox(height: PFSpacing.lg),
            Text(name, style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 8),
            Text(
              '$format • starts ${shortDate(DateTime.tryParse(startDate) ?? DateTime.now())}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _info() {
    final organizer = _league?['organizer_name']?.toString() ?? 'Organizer';
    final prize = _league?['prize']?.toString() ?? '';
    final location = _league?['location']?.toString() ?? '';
    final description = _league?['description']?.toString() ?? '';
    final entryFee = _league?['entry_fee']?.toString() ?? '0';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (description.isNotEmpty) ...[
          Text(description, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: PFSpacing.lg),
        ],
        Wrap(
          spacing: PFSpacing.sm,
          runSpacing: PFSpacing.sm,
          children: [
            PFBadge(label: organizer, icon: Icons.person_outline_rounded),
            if (location.isNotEmpty)
              PFBadge(label: location, icon: Icons.place_outlined),
            PFBadge(
                label: prize.isNotEmpty ? prize : 'No prize',
                icon: Icons.emoji_events_rounded),
            PFBadge(
                label: entryFee == '0' ? 'Free entry' : 'Br $entryFee',
                icon: Icons.payments_outlined),
          ],
        ),
      ],
    );
  }

  Widget _standingsTable() {
    Widget h(String t, {double? w, bool right = false}) => w == null
        ? Expanded(
            child: Text(t,
                textAlign: right ? TextAlign.right : TextAlign.left,
                style: Theme.of(context).textTheme.labelSmall))
        : SizedBox(
            width: w,
            child: Text(t,
                textAlign: right ? TextAlign.right : TextAlign.left,
                style: Theme.of(context).textTheme.labelSmall));

    return PFCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Column(
        children: [
          Row(children: [
            h('#', w: 28),
            const SizedBox(width: 8),
            h('TEAM'),
            h('P', w: 26, right: true),
            h('W/D/L', w: 52, right: true),
            h('GD', w: 34, right: true),
            h('PTS', w: 32, right: true),
          ]),
          const Divider(height: 18),
          ...List.generate(_standings.length, (i) {
            final s = _standings[i];
            final rank = s['rank'] ?? (i + 1);
            final name = s['team_name']?.toString() ?? 'Team';
            final pts = s['points'] ?? 0;
            final w = s['wins'] ?? 0;
            final d = s['draws'] ?? 0;
            final l = s['losses'] ?? 0;
            final mp = s['matches_played'] ?? 0;
            final gd = s['goal_difference'] ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: rank <= 3
                        ? Icon(Icons.military_tech_rounded,
                            size: 16, color: _medal(rank))
                        : Text('$rank',
                            style: TextStyle(
                                fontSize: 12, color: PFColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  SizedBox(
                    width: 26,
                    child: Text('$mp',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12.5, color: PFColors.textSecondary)),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text('$w/$d/$l',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12.5, color: PFColors.text)),
                  ),
                  SizedBox(
                    width: 34,
                    child: Text(gd >= 0 ? '+$gd' : '$gd',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: gd > 0
                              ? PFColors.primary
                              : (gd < 0 ? PFColors.danger : PFColors.textSecondary),
                        )),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text('$pts',
                        textAlign: TextAlign.right,
                        style: PFType.number.copyWith(fontSize: 14, color: PFColors.primary)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: PFColors.surface,
        border: Border(top: BorderSide(color: PFColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: PFButton(
            label: 'Join league',
            icon: Icons.emoji_events_outlined,
            onTap: _join,
          ),
        ),
      ),
    );
  }

  Color _medal(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFF5C24B);
      case 2:
        return PFColors.textSecondary;
      default:
        return const Color(0xFFCD7F45);
    }
  }
}
