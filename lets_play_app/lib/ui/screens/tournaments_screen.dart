import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/data/services/tournament_service.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_badge.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_skeleton.dart';
import '../widgets/pf_sport_tile.dart';

class TournamentsScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const TournamentsScreen({super.key, required this.session, required this.repo});

  @override
  State<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends State<TournamentsScreen> {
  List<Tournament> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await TournamentService.getTournaments();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
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
        title: const Text('Tournaments'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: PFColors.primary,
        backgroundColor: PFColors.surfaceRaised,
        child: _loading
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: const [
                  PFSkeletonCard(height: 96),
                  SizedBox(height: PFSpacing.sm),
                  PFSkeletonCard(height: 96),
                ],
              )
            : _items.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 40),
                    PFEmptyState(
                      icon: Icons.emoji_events_outlined,
                      title: 'No tournaments yet',
                      message: 'Brackets show up here once one is created.',
                    ),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: PFSpacing.md),
                    itemBuilder: (_, i) => _card(_items[i]),
                  ),
      ),
    );
  }

  Widget _card(Tournament t) {
    return PFCard(
      onTap: () => Navigator.pushNamed(
        context,
        '/tournament-details',
        arguments: {'id': t.id, 'name': t.name},
      ),
      child: Row(
        children: [
          PFSportTile(sport: t.sport, size: 52),
          const SizedBox(width: PFSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('${t.formatDisplay} · ${t.currentTeams}/${t.maxTeams} teams',
                    style: Theme.of(context).textTheme.bodySmall),
                if (t.prizePool.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(t.prizePool,
                      style: const TextStyle(
                          color: PFColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
          const SizedBox(width: PFSpacing.sm),
          PFBadge(
            label: t.statusDisplay.toUpperCase(),
            color: t.status == 'live'
                ? PFColors.danger
                : (t.status == 'completed' ? PFColors.textSecondary : PFColors.primary),
          ),
        ],
      ),
    );
  }
}
