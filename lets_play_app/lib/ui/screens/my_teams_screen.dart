import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_skeleton.dart';
import '../widgets/pf_sport_tile.dart';

class MyTeamsScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const MyTeamsScreen({super.key, required this.session, required this.repo});

  @override
  State<MyTeamsScreen> createState() => _MyTeamsScreenState();
}

class _MyTeamsScreenState extends State<MyTeamsScreen> {
  List<dynamic> _teams = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() => _loading = true);
    final teams = await widget.repo.getMyTeams(token, forceRefresh: forceRefresh);
    if (!mounted) return;
    setState(() {
      _teams = teams;
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
        title: const Text('My teams'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(forceRefresh: true),
        color: PFColors.primary,
        backgroundColor: PFColors.surfaceRaised,
        child: _loading
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: const [
                  PFSkeletonCard(height: 72),
                  SizedBox(height: PFSpacing.sm),
                  PFSkeletonCard(height: 72),
                ],
              )
            : _teams.isEmpty
                ? ListView(children: [
                    const SizedBox(height: 40),
                    PFEmptyState(
                      icon: PFIcons.teams,
                      title: 'No teams yet',
                      message: 'Create or join a team to see it here.',
                    ),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    itemCount: _teams.length,
                    separatorBuilder: (_, __) => const SizedBox(height: PFSpacing.sm),
                    itemBuilder: (_, i) {
                      final t = _teams[i];
                      final name = t['name']?.toString() ?? 'Team';
                      return PFCard(
                        onTap: () => Navigator.pushNamed(context, AppRoutes.teamDetails,
                            arguments: {'id': t['id'], 'name': name}),
                        child: Row(
                          children: [
                            PFSportTile(sport: t['sport']?.toString() ?? 'other', size: 48),
                            const SizedBox(width: PFSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.titleSmall),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${t['current_members'] ?? 0}/${t['max_members'] ?? 0} members'
                                    '${t['role'] != null ? ' · ${t['role']}' : ''}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: PFColors.textTertiary),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
