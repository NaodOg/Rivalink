import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/data/services/league_service.dart';
import '../../core/data/services/analytics_service.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../../core/utils/formatters.dart';
import '../widgets/pf_badge.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_segmented.dart';
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
  List<LeagueFixture> _fixtures = [];
  int _tab = 0;
  bool _loading = true;
  bool _error = false;

  bool get _isOrganizer => _league?['is_organizer'] == true;
  String get _status => _league?['status']?.toString() ?? 'registration';

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
        _fixtures = List<LeagueFixture>.from(result['fixtures'] ?? []);
        _loading = false;
        final loaded = _league;
        if (loaded != null) {
          AnalyticsService.event('league_viewed', {
            'league_id': widget.leagueId,
            'status': loaded['status']?.toString() ?? '',
            'current_teams': loaded['current_teams'] ?? 0,
          });
        }
        if (_fixtures.isEmpty && _tab == 1) _tab = 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _join() async {
    final token = widget.session.token;
    if (token == null) return;
    AnalyticsService.event('league_join_clicked', {
      'league_id': widget.leagueId,
    });
    final teams = await widget.repo.getMyTeams(token);
    if (!mounted) return;
    if (teams.isEmpty) {
      _snack('You need a team first');
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
    final res = await widget.repo.joinLeague(token, widget.leagueId, teamId);
    _snack((res['message'] ?? res['error'] ?? '').toString());
    _load();
  }

  Future<void> _startLeague() async {
    final token = widget.session.token;
    if (token == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PFColors.surfaceRaised,
        title: const Text('Start the season?'),
        content: const Text(
            'Registrations will close and the round-robin schedule will be generated. '
            'This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Start', style: TextStyle(color: PFColors.primary))),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await widget.repo.startLeague(token, widget.leagueId);
    _snack((res['message'] ?? res['error'] ?? '').toString());
    _load();
  }

  Future<void> _cancelLeague() async {
    final token = widget.session.token;
    if (token == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PFColors.surfaceRaised,
        title: const Text('Cancel this league?'),
        content: const Text('Entry fees are marked for refund and all teams are notified.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel league', style: TextStyle(color: PFColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await widget.repo.cancelLeague(token, widget.leagueId);
    _snack((res['message'] ?? res['error'] ?? '').toString());
    _load();
  }

  Future<void> _removeTeam(int teamId, String teamName) async {
    final token = widget.session.token;
    if (token == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PFColors.surfaceRaised,
        title: Text('Remove $teamName?'),
        content: const Text('They will be removed from the league before the season starts.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove', style: TextStyle(color: PFColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await widget.repo.removeLeagueTeam(
        token: token, leagueId: widget.leagueId, teamId: teamId);
    _snack((res['message'] ?? res['error'] ?? '').toString());
    _load();
  }

  // ── Fixture actions ──

  Future<void> _fixtureActions(LeagueFixture fixture) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PFColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(PFRadius.xl))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                '${fixture.homeTeamName} vs ${fixture.awayTeamName} · Round ${fixture.roundNumber}',
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.scoreboard_outlined, color: PFColors.primary),
              title: Text(fixture.isCompleted ? 'Correct result' : 'Record result'),
              onTap: () => Navigator.pop(ctx, 'result'),
            ),
            ListTile(
              leading: const Icon(Icons.schedule_rounded, color: PFColors.textSecondary),
              title: const Text('Reschedule'),
              onTap: () => Navigator.pop(ctx, 'reschedule'),
            ),
            if (fixture.matchId == null)
              ListTile(
                leading: const Icon(Icons.stadium_outlined, color: PFColors.textSecondary),
                title: const Text('Schedule as a match'),
                subtitle: const Text('Creates a real match players can join and chat in'),
                onTap: () => Navigator.pop(ctx, 'schedule'),
              )
            else
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded, color: PFColors.textSecondary),
                title: const Text('View match'),
                onTap: () => Navigator.pop(ctx, 'open'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'result':
        await _recordResultSheet(fixture);
      case 'reschedule':
        await _rescheduleSheet(fixture);
      case 'schedule':
        await _scheduleSheet(fixture);
      case 'open':
        if (fixture.matchId != null) {
          Navigator.pushNamed(context, AppRoutes.matchDetails, arguments: fixture.matchId);
        }
    }
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _recordResultSheet(LeagueFixture fixture) async {
    final token = widget.session.token;
    if (token == null) return;
    final homeCtrl = TextEditingController(text: fixture.homeScore?.toString() ?? '');
    final awayCtrl = TextEditingController(text: fixture.awayScore?.toString() ?? '');
    String walkover = '';

    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PFColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(PFRadius.xl))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Record result',
                      style: Theme.of(ctx).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fixture.homeTeamName, style: Theme.of(ctx).textTheme.labelSmall),
                            const SizedBox(height: 6),
                            TextField(
                              controller: homeCtrl,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(hintText: '0'),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('—', style: TextStyle(fontSize: 20, color: PFColors.muted)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fixture.awayTeamName, style: Theme.of(ctx).textTheme.labelSmall),
                            const SizedBox(height: 6),
                            TextField(
                              controller: awayCtrl,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(hintText: '0'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Walkover', style: Theme.of(ctx).textTheme.labelSmall),
                  const SizedBox(height: 8),
                  PFSegmented(
                    labels: const ['None', 'Home', 'Away'],
                    index: walkover.isEmpty ? 0 : (walkover == 'home' ? 1 : 2),
                    onChanged: (i) => setSheetState(
                        () => walkover = i == 0 ? '' : (i == 1 ? 'home' : 'away')),
                  ),
                  const SizedBox(height: 20),
                  PFButton(label: 'Save result', onTap: () => Navigator.pop(ctx, true)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (save != true) return;

    final home = int.tryParse(homeCtrl.text.trim()) ?? 0;
    final away = int.tryParse(awayCtrl.text.trim()) ?? 0;
    final res = await widget.repo.recordFixtureResult(
      token: token,
      fixtureId: fixture.id,
      homeScore: home,
      awayScore: away,
      walkover: walkover,
    );
    if (res['success'] == true && res['league_status'] == 'completed') {
      _snack('Result saved — league complete!');
    } else {
      _snack((res['message'] ?? res['error'] ?? '').toString());
    }
    _load();
  }

  Future<void> _rescheduleSheet(LeagueFixture fixture) async {
    final token = widget.session.token;
    if (token == null) return;
    final current = DateTime.tryParse(fixture.kickoff ?? '')?.toLocal() ?? DateTime.now();
    final picked = await _pickDateTime(current);
    if (picked == null) return;
    final res = await widget.repo.rescheduleFixture(
        token: token, fixtureId: fixture.id, kickoff: picked);
    _snack((res['message'] ?? res['error'] ?? 'Fixture rescheduled').toString());
    _load();
  }

  Future<void> _scheduleSheet(LeagueFixture fixture) async {
    final token = widget.session.token;
    if (token == null) return;
    final current = DateTime.tryParse(fixture.kickoff ?? '')?.toLocal() ?? DateTime.now();
    final picked = await _pickDateTime(current);
    if (picked == null) return;
    final res = await widget.repo.scheduleFixture(
        token: token, fixtureId: fixture.id, dateTime: picked);
    _snack((res['message'] ?? res['error'] ?? 'Match scheduled').toString());
    _load();
  }

  // ── Build ──

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
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: PFColors.primary,
                      backgroundColor: PFColors.surfaceRaised,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        children: [
                          _hero(),
                          const SizedBox(height: PFSpacing.lg),
                          if (_status == 'completed' &&
                              _league?['champion_team_name'] != null) ...[
                            _championBanner(),
                            const SizedBox(height: PFSpacing.lg),
                          ],
                          _info(),
                          ..._nextFixtureBlock(),
                          PFSegmented(
                            labels: const ['Standings', 'Fixtures', 'Teams'],
                            index: _tab,
                            onChanged: (i) => setState(() => _tab = i),
                          ),
                          const SizedBox(height: PFSpacing.lg),
                          if (_tab == 0) _standingsSection(),
                          if (_tab == 1) _fixturesSection(),
                          if (_tab == 2) _teamsSection(),
                        ],
                      ),
                    ),
      bottomNavigationBar: _league != null && _bottomBar() != null ? _bottomBar() : null,
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
                const SizedBox(width: PFSpacing.md),
                _statusBadge(),
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

  Widget _statusBadge() {
    final (label, color) = switch (_status) {
      'live' => ('LIVE', PFColors.success),
      'completed' => ('COMPLETED', PFColors.primary),
      'cancelled' => ('CANCELLED', PFColors.danger),
      _ => ('REGISTRATION', PFColors.warning),
    };
    return PFBadge(label: label, color: color);
  }

  Widget _championBanner() {
    final champion = _league?['champion_team_name']?.toString() ?? '';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PFColors.gold.withValues(alpha: 0.20),
            PFColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(PFRadius.xl),
        border: Border.all(color: PFColors.gold.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_rounded, color: PFColors.gold, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Champion', style: Theme.of(context).textTheme.labelSmall),
                Text(champion, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _nextFixtureBlock() {
    final upcoming = _fixtures.where((f) => !f.isCompleted).toList()
      ..sort((a, b) {
        final ka = DateTime.tryParse(a.kickoff ?? '') ?? DateTime(3000);
        final kb = DateTime.tryParse(b.kickoff ?? '') ?? DateTime(3000);
        return ka.compareTo(kb);
      });
    if (upcoming.isEmpty) return const [];
    final f = upcoming.first;
    final kickoff = DateTime.tryParse(f.kickoff ?? '')?.toLocal();
    final diff = kickoff?.difference(DateTime.now());
    final soon = diff != null && !diff.isNegative && diff.inHours < 24;

    return [
      const SizedBox(height: PFSpacing.lg),
      PFCard(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: PFColors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(PFRadius.sm),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.calendar_month_rounded,
                  size: 20, color: PFColors.primary),
            ),
            const SizedBox(width: PFSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NEXT FIXTURE',
                      style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700,
                          color: PFColors.textTertiary)),
                  const SizedBox(height: 2),
                  Text(
                    '${f.homeTeamName} vs ${f.awayTeamName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(_fmtKickoff(f.kickoff),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (soon)
              PFBadge(
                label: diff.inHours < 1 ? 'Starts soon' : 'In ${diff.inHours}h',
                color: PFColors.warning,
              ),
          ],
        ),
      ),
      const SizedBox(height: PFSpacing.xl),
    ];
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

  // ── Sections ──

  Widget _standingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_standings.isEmpty)
          const PFEmptyState(
            icon: Icons.emoji_events_rounded,
            title: 'No teams yet',
            message: 'Standings appear once teams join and results come in.',
          )
        else
          _standingsTable(),
      ],
    );
  }

  Widget _fixturesSection() {
    if (_fixtures.isEmpty) {
      return const PFEmptyState(
        icon: Icons.calendar_month_rounded,
        title: 'No fixtures yet',
        message: 'The schedule is generated when the organizer starts the season.',
      );
    }
    final byRound = <int, List<LeagueFixture>>{};
    for (final f in _fixtures) {
      byRound.putIfAbsent(f.roundNumber, () => []).add(f);
    }
    final rounds = byRound.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final round in rounds) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('ROUND $round', style: Theme.of(context).textTheme.labelSmall),
          ),
          ...byRound[round]!.map(_fixtureCard),
          const SizedBox(height: PFSpacing.lg),
        ],
      ],
    );
  }

  Widget _fixtureCard(LeagueFixture fixture) {
    final canManage = _isOrganizer && _status == 'live';
    return Padding(
      padding: const EdgeInsets.only(bottom: PFSpacing.sm),
      child: PFCard(
        onTap: canManage ? () => _fixtureActions(fixture) : null,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    fixture.homeTeamName,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: fixture.isCompleted
                      ? Text('${fixture.homeScore} – ${fixture.awayScore}',
                          style: PFType.number.copyWith(fontSize: 17, color: PFColors.text))
                      : Text('vs',
                          style: TextStyle(fontSize: 13, color: PFColors.textSecondary)),
                ),
                Expanded(
                  child: Text(
                    fixture.awayTeamName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.schedule_rounded, size: 13, color: PFColors.textTertiary),
                const SizedBox(width: 4),
                Text(
                  _fmtKickoff(fixture.kickoff),
                  style: TextStyle(fontSize: 11.5, color: PFColors.textTertiary),
                ),
                if (fixture.isWalkover) ...[
                  const SizedBox(width: 8),
                  const PFBadge(label: 'Walkover'),
                ],
                if (fixture.matchId != null) ...[
                  const SizedBox(width: 8),
                  const PFBadge(label: 'Match'),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamsSection() {
    if (_standings.isEmpty) {
      return const PFEmptyState(
        icon: Icons.groups_rounded,
        title: 'No teams yet',
        message: 'Be the first to join this league.',
      );
    }
    final canRemove = _isOrganizer && _status == 'registration';
    return Column(
      children: [
        for (final s in _standings)
          Padding(
            padding: const EdgeInsets.only(bottom: PFSpacing.sm),
            child: PFCard(
              child: Row(
                children: [
                  PFSportTile(
                      sport: _league?['sport']?.toString() ?? 'other', size: 40),
                  const SizedBox(width: PFSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s['team_name']?.toString() ?? 'Team',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall),
                        Text(
                          '${s['wins'] ?? 0}W · ${s['draws'] ?? 0}D · ${s['losses'] ?? 0}L · ${s['points'] ?? 0} pts',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (canRemove)
                    IconButton(
                      tooltip: 'Remove team',
                      icon: const Icon(Icons.person_remove_outlined,
                          size: 20, color: PFColors.danger),
                      onPressed: () => _removeTeam(
                          s['team_id'] as int, s['team_name']?.toString() ?? 'Team'),
                    ),
                ],
              ),
            ),
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
            h('#', w: 44),
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
            final mine = s['is_mine'] == true;
            final prev = (s['prev_rank'] ?? 0) as int;
            return Container(
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              decoration: mine
                  ? BoxDecoration(
                      color: PFColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(PFRadius.sm),
                      border: const Border(
                        left: BorderSide(color: PFColors.primary, width: 3),
                      ),
                    )
                  : null,
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          child: rank <= 3
                              ? Icon(Icons.military_tech_rounded,
                                  size: 16, color: _medal(rank))
                              : Text('$rank',
                                  style: TextStyle(
                                      fontSize: 12, color: PFColors.textSecondary)),
                        ),
                        if (prev != 0 && prev > rank)
                          const Icon(Icons.arrow_drop_up_rounded,
                              size: 16, color: PFColors.success)
                        else if (prev != 0 && prev < rank)
                          const Icon(Icons.arrow_drop_down_rounded,
                              size: 16, color: PFColors.danger),
                      ],
                    ),
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

  Widget? _bottomBar() {
    if (_isOrganizer && _status == 'registration') {
      return _bottomContainer(
        Row(
          children: [
            Expanded(
              child: PFButton(
                label: 'Cancel league',
                variant: PFButtonVariant.ghost,
                onTap: _cancelLeague,
              ),
            ),
            const SizedBox(width: PFSpacing.sm),
            Expanded(
              child: PFButton(
                label: 'Start league',
                icon: Icons.play_arrow_rounded,
                onTap: _startLeague,
              ),
            ),
          ],
        ),
      );
    }
    if (_isOrganizer && _status == 'live') {
      return _bottomContainer(
        PFButton(
          label: 'Cancel league',
          variant: PFButtonVariant.secondary,
          onTap: _cancelLeague,
        ),
      );
    }
    if (!_isOrganizer && _status == 'registration') {
      return _bottomContainer(
        PFButton(
          label: 'Join league',
          icon: Icons.emoji_events_outlined,
          onTap: _join,
        ),
      );
    }
    return null;
  }

  Widget _bottomContainer(Widget child) {
    return Container(
      decoration: const BoxDecoration(
        color: PFColors.surface,
        border: Border(top: BorderSide(color: PFColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: child,
        ),
      ),
    );
  }

  String _fmtKickoff(String? iso) {
    final dt = DateTime.tryParse(iso ?? '')?.toLocal();
    if (dt == null) return 'Date TBD';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day} · $h:$m';
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
