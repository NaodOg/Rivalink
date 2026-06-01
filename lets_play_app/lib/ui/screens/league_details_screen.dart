import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/playfair_theme.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_scaffold.dart';



class LeagueDetailsScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  final int leagueId;
  final String leagueName;
  const LeagueDetailsScreen({super.key, required this.session, required this.repo, required this.leagueId, required this.leagueName});

  @override
  State<LeagueDetailsScreen> createState() => _LeagueDetailsScreenState();
}

class _LeagueDetailsScreenState extends State<LeagueDetailsScreen> {
  Map<String, dynamic>? _league;
  List<dynamic> _standings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    final result = await widget.repo.getLeagueDetails(token, widget.leagueId);
    if (!mounted) return;
    setState(() {
      _league = result['league'] as Map<String, dynamic>?;
      _standings = List<dynamic>.from(result['standings'] ?? []);
      _loading = false;
    });
  }

  Future<void> _join() async {
    final token = widget.session.token;
    if (token == null) return;

    final teams = await widget.repo.getMyTeams(token);
    if (!mounted) return;

    if (teams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need to create or join a team first')),
      );
      return;
    }

    if (teams.length == 1) {
      final res = await widget.repo.joinLeague(token, widget.leagueId, teams[0]['id'] as int);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((res['message'] ?? res['error'] ?? '').toString())));
      _load();
      return;
    }

    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: PFColors.card,
        title: const Text('Choose a team', style: TextStyle(color: PFColors.text)),
        children: teams.map<Widget>((t) {
          final name = t['name']?.toString() ?? 'Team';
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, t['id'] as int),
            child: Text(name, style: const TextStyle(color: PFColors.text, fontSize: 15)),
          );
        }).toList(),
      ),
    );

    if (selected == null) return;
    final res = await widget.repo.joinLeague(token, widget.leagueId, selected);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((res['message'] ?? res['error'] ?? '').toString())));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return PFScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.leagueName),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PFColors.accent))
          : _league == null
              ? const Center(child: Text('League not found', style: TextStyle(color: PFColors.muted)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 14),
                    _buildInfoCard(),
                    const SizedBox(height: 16),
                    _buildStandingsTitle(),
                    const SizedBox(height: 8),
                    _buildStandingsTable(),
                    if (_standings.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 20),
                        child: Center(child: Text('No teams have joined yet.', style: TextStyle(color: PFColors.muted))),
                      ),
                    const SizedBox(height: 20),
                    PFButton(label: 'Join League', onTap: _join),
                    const SizedBox(height: 20),
                  ],
                ),
    );
  }

  Widget _buildHeader() {
    final sport = _league?['sport']?.toString() ?? 'sport';
    final format = _league?['format']?.toString() ?? 'League';
    final name = _league?['name']?.toString() ?? widget.leagueName;
    final current = _league?['current_teams'] ?? 0;
    final max = _league?['max_teams'] ?? 8;
    final startDate = _league?['start_date']?.toString() ?? '';

    return PFCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _sportGradient(sport),
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_sportIcon(sport), color: PFColors.accent, size: 20),
                  const SizedBox(width: 8),
                  Text(sport.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: PFColors.accent, letterSpacing: 1.2)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: PFColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('$current / $max teams', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: PFColors.accent)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('$format • ${_formatDate(startDate)}', style: const TextStyle(fontSize: 13, color: PFColors.muted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final organizer = _league?['organizer_name']?.toString() ?? 'Organizer';
    final prize = _league?['prize']?.toString() ?? '';
    final location = _league?['location']?.toString() ?? '';
    final description = _league?['description']?.toString() ?? '';
    final entryFee = _league?['entry_fee']?.toString() ?? '0';

    return PFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description.isNotEmpty) ...[
            Text(description, style: const TextStyle(fontSize: 14, color: PFColors.text, height: 1.5)),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              _infoChip(Icons.person_outline_rounded, organizer),
              if (location.isNotEmpty) ...[
                const SizedBox(width: 12),
                _infoChip(Icons.location_on_rounded, location),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _infoChip(Icons.emoji_events_rounded, prize.isNotEmpty ? prize : 'No prize'),
              const SizedBox(width: 12),
              _infoChip(Icons.monetization_on_rounded, entryFee == '0' ? 'Free entry' : 'Br $entryFee'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 14, color: PFColors.muted),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: const TextStyle(fontSize: 12, color: PFColors.muted), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildStandingsTitle() {
    return Row(
      children: [
        const Text('Standings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const Spacer(),
        Text('${_standings.length} team${_standings.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 12, color: PFColors.muted)),
      ],
    );
  }

  Widget _buildStandingsTable() {
    return PFCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: const [
              SizedBox(width: 28, child: Text('#', style: TextStyle(color: PFColors.muted, fontSize: 11, fontWeight: FontWeight.w700))),
              SizedBox(width: 8),
              Expanded(child: Text('Team', style: TextStyle(color: PFColors.muted, fontSize: 11, fontWeight: FontWeight.w700))),
              SizedBox(width: 24, child: Text('P', textAlign: TextAlign.right, style: TextStyle(color: PFColors.muted, fontSize: 11, fontWeight: FontWeight.w700))),
              SizedBox(width: 48, child: Text('W/D/L', textAlign: TextAlign.right, style: TextStyle(color: PFColors.muted, fontSize: 11, fontWeight: FontWeight.w700))),
              SizedBox(width: 32, child: Text('GD', textAlign: TextAlign.right, style: TextStyle(color: PFColors.muted, fontSize: 11, fontWeight: FontWeight.w700))),
              SizedBox(width: 28, child: Text('Pts', textAlign: TextAlign.right, style: TextStyle(color: PFColors.muted, fontSize: 11, fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 8),
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
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: i < _standings.length - 1 ? Border(bottom: BorderSide(color: PFColors.border.withValues(alpha: 0.2))) : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: rank <= 3
                        ? Icon(Icons.emoji_events_rounded, size: 16, color: rank == 1 ? Colors.amber : rank == 2 ? Colors.grey[400] : Colors.brown[300])
                        : Text('$rank', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PFColors.muted)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  ),
                  SizedBox(
                    width: 24,
                    child: Text('$mp', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: PFColors.muted)),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text('$w/$d/$l', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: PFColors.text)),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(gd >= 0 ? '+$gd' : '$gd', textAlign: TextAlign.right, style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: gd > 0 ? PFColors.accent : (gd < 0 ? Colors.redAccent : PFColors.muted),
                    )),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text('$pts', textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: PFColors.accent)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatDate(String dateTimeStr) {
    final dt = DateTime.tryParse(dateTimeStr);
    if (dt == null) return dateTimeStr;
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  IconData _sportIcon(String sport) {
    final s = sport.toLowerCase();
    if (s.contains('soccer') || s.contains('football')) return Icons.sports_soccer_rounded;
    if (s.contains('basketball')) return Icons.sports_basketball_rounded;
    if (s.contains('tennis')) return Icons.sports_tennis_rounded;
    if (s.contains('volleyball')) return Icons.sports_volleyball_rounded;
    return Icons.emoji_events_rounded;
  }

  List<Color> _sportGradient(String sport) {
    final s = sport.toLowerCase();
    if (s.contains('soccer') || s.contains('football')) return const [Color(0xFF1A3A1A), Color(0xFF0D1F0D)];
    if (s.contains('basketball')) return const [Color(0xFF3A1A1A), Color(0xFF1F0D0D)];
    if (s.contains('tennis')) return const [Color(0xFF2A3A1A), Color(0xFF141F0D)];
    return const [Color(0xFF1A2A3A), Color(0xFF0D141F)];
  }
}
