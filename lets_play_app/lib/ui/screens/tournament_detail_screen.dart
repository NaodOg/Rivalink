import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/data/services/tournament_service.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_badge.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_section_header.dart';
import '../widgets/pf_sport_tile.dart';

class TournamentDetailScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  final int tournamentId;
  final String tournamentName;
  const TournamentDetailScreen({
    super.key,
    required this.session,
    required this.repo,
    required this.tournamentId,
    required this.tournamentName,
  });

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen> {
  Tournament? _t;
  List<TournamentTeam> _teams = [];
  List<TournamentMatch> _matches = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    final res = await TournamentService.getTournamentDetails(widget.tournamentId);
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() {
        _t = res['tournament'] as Tournament;
        _teams = (res['teams'] as List).cast<TournamentTeam>();
        _matches = (res['matches'] as List).cast<TournamentMatch>();
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = true;
      });
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
        title: Text(widget.tournamentName),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PFColors.primary))
          : _error
              ? Center(
                  child: PFEmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: "Couldn't load tournament",
                    actionLabel: 'Retry',
                    onAction: _load,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    _hero(),
                    const SizedBox(height: PFSpacing.xxl),
                    PFSectionHeader(
                      eyebrow: 'Field',
                      title: 'Teams',
                      trailing: PFBadge(label: '${_teams.length}'),
                    ),
                    const SizedBox(height: PFSpacing.md),
                    if (_teams.isEmpty)
                      const PFEmptyState(icon: Icons.groups_outlined, title: 'No teams registered')
                    else
                      Wrap(
                        spacing: PFSpacing.sm,
                        runSpacing: PFSpacing.sm,
                        children: _teams
                            .map((tt) => PFBadge(
                                  label: '${tt.seed}. ${tt.teamName}',
                                  color: tt.status == 'eliminated'
                                      ? PFColors.textSecondary
                                      : PFColors.primary,
                                ))
                            .toList(),
                      ),
                    const SizedBox(height: PFSpacing.xxl),
                    PFSectionHeader(eyebrow: 'Knockout', title: 'Bracket'),
                    const SizedBox(height: PFSpacing.md),
                    if (_matches.isEmpty)
                      const PFEmptyState(
                        icon: Icons.account_tree_outlined,
                        title: 'Bracket not ready',
                        message: 'The bracket is generated when the tournament starts.',
                      )
                    else
                      _bracket(),
                  ],
                ),
    );
  }

  Widget _hero() {
    final t = _t!;
    final color = PFSport.color(t.sport);
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
                PFSportTile(sport: t.sport, size: 44),
                const Spacer(),
                PFBadge(
                  label: t.statusDisplay.toUpperCase(),
                  color: t.status == 'live' ? PFColors.danger : PFColors.primary,
                ),
              ],
            ),
            const SizedBox(height: PFSpacing.lg),
            Text(t.name, style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 8),
            Text('${t.formatDisplay} · ${t.currentTeams}/${t.maxTeams} teams',
                style: Theme.of(context).textTheme.bodyMedium),
            if (t.prizePool.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(t.prizePool,
                  style: const TextStyle(
                      color: PFColors.primary, fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bracket() {
    final rounds = <int, List<TournamentMatch>>{};
    for (final m in _matches) {
      rounds.putIfAbsent(m.roundNumber, () => []).add(m);
    }
    final keys = rounds.keys.toList()..sort();

    return SizedBox(
      height: 340,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: keys.length,
        separatorBuilder: (_, __) => const SizedBox(width: PFSpacing.md),
        itemBuilder: (_, i) {
          final round = keys[i];
          final matches = rounds[round]!..sort((a, b) => a.matchNumber.compareTo(b.matchNumber));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_roundName(round, keys.length).toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: PFSpacing.sm),
              Expanded(
                child: ListView.separated(
                  itemCount: matches.length,
                  separatorBuilder: (_, __) => const SizedBox(height: PFSpacing.sm),
                  itemBuilder: (_, j) => _matchCard(matches[j]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _roundName(int round, int total) {
    if (round == total) return 'Final';
    if (round == total - 1) return 'Semifinal';
    if (round == total - 2) return 'Quarterfinal';
    return 'Round $round';
  }

  Widget _matchCard(TournamentMatch m) {
    final played = m.status == 'completed';
    Widget team(String name, int? seed, bool isWinner, int score) {
      return Row(
        children: [
          Expanded(
            child: Text(
              seed != null ? '$seed. $name' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isWinner ? FontWeight.w800 : FontWeight.w500,
                color: isWinner ? PFColors.primary : PFColors.text,
              ),
            ),
          ),
          if (played)
            Text('$score',
                style: PFType.number.copyWith(
                    fontSize: 13,
                    color: isWinner ? PFColors.primary : PFColors.textSecondary)),
        ],
      );
    }

    return Container(
      width: 190,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: PFColors.surface,
        borderRadius: BorderRadius.circular(PFRadius.md),
        border: Border.all(color: PFColors.border),
      ),
      child: Column(
        children: [
          team(m.team1Name, m.team1Seed, played && m.winnerId == m.team1Id, m.score1),
          const SizedBox(height: 6),
          const Divider(height: 1, color: PFColors.hairline),
          const SizedBox(height: 6),
          team(m.team2Name, m.team2Seed, played && m.winnerId == m.team2Id, m.score2),
        ],
      ),
    );
  }
}
