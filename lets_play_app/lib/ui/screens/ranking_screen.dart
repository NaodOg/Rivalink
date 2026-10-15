import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/data/services/ranking_service.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_segmented.dart';

class RankingScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const RankingScreen({super.key, required this.session, required this.repo});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  int _tab = 0;
  String _sport = '';
  List<Map<String, dynamic>> _rankings = [];
  bool _loading = true;

  static const _sports = [
    ('', 'All'),
    ('soccer', 'Soccer'),
    ('basketball', 'Basketball'),
    ('tennis', 'Tennis'),
    ('volleyball', 'Volleyball'),
    ('badminton', 'Badminton'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() => _loading = true);
    try {
      final result = _tab == 0
          ? await RankingService.getIndividualRankings(
              token: token, sport: _sport.isEmpty ? null : _sport)
          : await RankingService.getTeamRankings(
              token: token, sport: _sport.isEmpty ? null : _sport);
      if (!mounted) return;
      final raw = result['rankings'] as List<dynamic>? ?? [];
      setState(() {
        _rankings = raw.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _rankings = [];
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
                Text('Rankings', style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: PFSpacing.lg),
                PFSegmented(
                  labels: const ['Individual', 'Teams'],
                  index: _tab,
                  onChanged: (i) {
                    setState(() => _tab = i);
                    _load();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: PFSpacing.md),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _sports.length,
              separatorBuilder: (_, __) => const SizedBox(width: PFSpacing.sm),
              itemBuilder: (_, i) {
                final (code, label) = _sports[i];
                return Center(
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _sport == code,
                    onSelected: (_) {
                      setState(() => _sport = code);
                      _load();
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: PFSpacing.md),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: PFColors.primary,
              backgroundColor: PFColors.surfaceRaised,
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: PFColors.primary))
                  : _rankings.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 40),
                            PFEmptyState(
                              icon: Icons.leaderboard_rounded,
                              title: 'No rankings yet',
                              message: 'Play premium matches to appear on the board.',
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          itemCount: _rankings.length + 1,
                          itemBuilder: (context, i) {
                            if (i == 0) return _header();
                            return _row(_rankings[i - 1], i);
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    Widget cell(String t, {double? width, bool right = false}) => width != null
        ? SizedBox(
            width: width,
            child: Text(t,
                textAlign: right ? TextAlign.right : TextAlign.left,
                style: Theme.of(context).textTheme.labelSmall))
        : Expanded(
            child: Text(t,
                textAlign: right ? TextAlign.right : TextAlign.left,
                style: Theme.of(context).textTheme.labelSmall));
    return Padding(
      padding: const EdgeInsets.only(bottom: PFSpacing.sm),
      child: Row(
        children: [
          cell('#', width: 30),
          const SizedBox(width: 8),
          cell(_tab == 0 ? 'PLAYER' : 'TEAM'),
          if (_tab == 0) cell('ELO', width: 52, right: true),
          if (_tab != 0) cell('PTS', width: 44, right: true),
          cell('W/D/L', width: 64, right: true),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> e, int rank) {
    final name = _tab == 0
        ? (e['name']?.toString() ?? 'Unknown')
        : (e['team_name']?.toString() ?? 'Unknown');
    final primaryVal = _tab == 0 ? (e['elo_rating'] ?? 1200) : (e['points'] ?? 0);
    final w = e['wins'] ?? 0;
    final d = e['draws'] ?? 0;
    final l = e['losses'] ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: PFSpacing.sm),
      child: PFCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: rank <= 3
                  ? Icon(Icons.military_tech_rounded,
                      size: 18, color: _medal(rank))
                  : Text('$rank',
                      style: PFType.number.copyWith(
                          fontSize: 13, color: PFColors.textSecondary)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            SizedBox(
              width: _tab == 0 ? 52 : 44,
              child: Text('$primaryVal',
                  textAlign: TextAlign.right,
                  style: PFType.number
                      .copyWith(fontSize: 15, color: PFColors.primary)),
            ),
            SizedBox(
              width: 64,
              child: Text('$w/$d/$l',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12.5, color: PFColors.textSecondary)),
            ),
          ],
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
