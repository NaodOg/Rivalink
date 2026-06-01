import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/data/services/ranking_service.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/playfair_theme.dart';
import '../widgets/pf_card.dart';

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

  final _sports = ['', 'soccer', 'basketball', 'tennis', 'volleyball', 'badminton'];

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
      Map<String, dynamic> result;
      if (_tab == 0) {
        result = await RankingService.getIndividualRankings(token: token, sport: _sport.isEmpty ? null : _sport);
      } else {
        result = await RankingService.getTeamRankings(token: token, sport: _sport.isEmpty ? null : _sport);
      }
      if (!mounted) return;
      final raw = result['rankings'] as List<dynamic>? ?? [];
      setState(() {
        _rankings = raw.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Rankings', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                ),
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: PFColors.card,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      _ToggleChip(label: 'Individual', selected: _tab == 0, onTap: () => setState(() { _tab = 0; _load(); })),
                      _ToggleChip(label: 'Teams', selected: _tab == 1, onTap: () => setState(() { _tab = 1; _load(); })),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  height: 40,
                  decoration: BoxDecoration(
                    color: PFColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: PFColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _sport,
                      dropdownColor: PFColors.card,
                      items: [
                        const DropdownMenuItem(value: '', child: Text('All Sports', style: TextStyle(color: PFColors.text, fontSize: 13))),
                        ..._sports.where((s) => s.isNotEmpty).map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s[0].toUpperCase() + s.substring(1), style: const TextStyle(color: PFColors.text, fontSize: 13)),
                        )),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _sport = v);
                        _load();
                      },
                    ),
                  ),
                ),
                const Spacer(),
                if (_rankings.isNotEmpty)
                  Text('${_rankings.length} ${_rankings.length == 1 ? 'entry' : 'entries'}',
                    style: const TextStyle(color: PFColors.muted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: PFColors.accent,
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: PFColors.accent))
                  : _rankings.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 80),
                            Center(child: Text('No rankings available yet.', style: TextStyle(color: PFColors.muted))),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _rankings.length + 1,
                          itemBuilder: (context, i) {
                            if (i == 0) return _buildHeader();
                            final entry = _rankings[i - 1];
                            return _buildRow(entry, i);
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    if (_tab == 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: const [
            SizedBox(width: 32, child: Text('#', style: TextStyle(color: PFColors.muted, fontSize: 11, fontWeight: FontWeight.w600))),
            SizedBox(width: 8),
            Expanded(child: Text('Player', style: TextStyle(color: PFColors.muted, fontSize: 11, fontWeight: FontWeight.w600))),
            SizedBox(width: 48, child: Text('ELO', textAlign: TextAlign.right, style: TextStyle(color: PFColors.muted, fontSize: 11, fontWeight: FontWeight.w600))),
            SizedBox(width: 64, child: Text('W/L/D', textAlign: TextAlign.right, style: TextStyle(color: PFColors.muted, fontSize: 11, fontWeight: FontWeight.w600))),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: const [
          SizedBox(width: 32, child: Text('#', style: TextStyle(color: PFColors.muted, fontSize: 11, fontWeight: FontWeight.w600))),
          SizedBox(width: 8),
          Expanded(child: Text('Team', style: TextStyle(color: PFColors.muted, fontSize: 11, fontWeight: FontWeight.w600))),
          SizedBox(width: 32, child: Text('Pts', textAlign: TextAlign.right, style: TextStyle(color: PFColors.muted, fontSize: 11, fontWeight: FontWeight.w600))),
          SizedBox(width: 64, child: Text('W/L/D', textAlign: TextAlign.right, style: TextStyle(color: PFColors.muted, fontSize: 11, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> entry, int rank) {
    if (_tab == 0) {
      final elo = entry['elo_rating'] ?? 1200;
      final w = entry['wins'] ?? 0;
      final l = entry['losses'] ?? 0;
      final d = entry['draws'] ?? 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: PFCard(
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text('$rank', style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: rank <= 3 ? PFColors.accent : PFColors.text,
                )),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(entry['name']?.toString() ?? 'Unknown',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 48,
                child: Text('$elo', textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: PFColors.accent)),
              ),
              SizedBox(
                width: 64,
                child: Text('$w/$l/$d', textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13, color: PFColors.muted)),
              ),
            ],
          ),
        ),
      );
    }

    final pts = entry['points'] ?? 0;
    final w = entry['wins'] ?? 0;
    final l = entry['losses'] ?? 0;
    final d = entry['draws'] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: PFCard(
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text('$rank', style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: rank <= 3 ? PFColors.accent : PFColors.text,
              )),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry['team_name']?.toString() ?? 'Unknown',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry['goal_difference'] != null)
                    Text('GD: ${entry['goal_difference'] >= 0 ? '+' : ''}${entry['goal_difference']}',
                      style: const TextStyle(fontSize: 11, color: PFColors.muted)),
                ],
              ),
            ),
            SizedBox(
              width: 32,
              child: Text('$pts', textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: PFColors.accent)),
            ),
            SizedBox(
              width: 64,
              child: Text('$w/$l/$d', textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, color: PFColors.muted)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? PFColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600,
          color: selected ? PFColors.background : PFColors.muted,
        )),
      ),
    );
  }
}
