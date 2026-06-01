import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/playfair_theme.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_scaffold.dart';

class MatchDetailsScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  final int matchId;
  const MatchDetailsScreen({super.key, required this.session, required this.repo, required this.matchId});

  @override
  State<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends State<MatchDetailsScreen> {
  Map<String, dynamic>? _match;
  List<dynamic> _players = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    try {
      final details = await widget.repo.getMatchDetails(token, widget.matchId);
      if (!mounted) return;
      setState(() {
        _match = details['match'] as Map<String, dynamic>?;
        _players = List<dynamic>.from(details['participants'] ?? []);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _join() async {
    final token = widget.session.token;
    if (token == null) return;
    final res = await widget.repo.joinMatch(token, widget.matchId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((res['message'] ?? res['error'] ?? '').toString())));
    _load();
  }

  bool get _isOrganizer {
    final userId = widget.session.user?['id'];
    return _match?['organizer'] == userId || _match?['organizer_id'] == userId;
  }

  bool get _isTeamSport {
    final sport = _match?['sport']?.toString().toLowerCase() ?? '';
    return ['soccer', 'basketball', 'volleyball'].contains(sport);
  }

  void _showSubmitResultSheet() {
    final teamA = <Map<String, dynamic>>[];
    final teamB = <Map<String, dynamic>>[];
    final unassigned = <Map<String, dynamic>>[];
    String winningGroup = '';
    final scoreController = TextEditingController();

    for (final p in _players) {
      final group = p['team_group']?.toString() ?? '';
      if (group == 'A') teamA.add(p);
      else if (group == 'B') teamB.add(p);
      else unassigned.add(p);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PFColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            void assignPlayer(Map<String, dynamic> player, String group) {
              setSheetState(() {
                unassigned.remove(player);
                teamA.remove(player);
                teamB.remove(player);
                if (group == 'A') teamA.add(player);
                else if (group == 'B') teamB.add(player);
                else unassigned.add(player);
              });
            }

            _buildPlayerRow(Map<String, dynamic> p, String currentGroup) {
              final name = (p['name'] ?? 'Player').toString();
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: currentGroup == 'A'
                          ? PFColors.accent.withValues(alpha: 0.25)
                          : currentGroup == 'B'
                              ? Colors.orange.withValues(alpha: 0.25)
                              : PFColors.cardSoft,
                      child: Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    if (currentGroup == 'A')
                      const Icon(Icons.circle, color: PFColors.accent, size: 10)
                    else if (currentGroup == 'B')
                      const Icon(Icons.circle, color: Colors.orange, size: 10),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 28,
                      child: PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.swap_horiz_rounded, size: 18, color: PFColors.muted),
                        onSelected: (g) => assignPlayer(p, g),
                        itemBuilder: (_) => [
                          if (currentGroup != 'A') const PopupMenuItem(value: 'A', child: Text('Team A', style: TextStyle(fontSize: 13))),
                          if (currentGroup != 'B') const PopupMenuItem(value: 'B', child: Text('Team B', style: TextStyle(fontSize: 13))),
                          if (currentGroup != '') const PopupMenuItem(value: '', child: Text('Unassign', style: TextStyle(fontSize: 13))),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.85,
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: PFColors.muted, borderRadius: BorderRadius.circular(2)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: Row(
                        children: [
                          const Expanded(child: Text('Submit Result', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    if (_isTeamSport) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setSheetState(() => winningGroup = winningGroup == 'A' ? '' : 'A'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: winningGroup == 'A' ? PFColors.accent.withValues(alpha: 0.2) : PFColors.card,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: winningGroup == 'A' ? PFColors.accent : PFColors.border, width: winningGroup == 'A' ? 2 : 1),
                                  ),
                                  child: Column(
                                    children: [
                                      Text('Team A (${teamA.length})', style: TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w700,
                                        color: winningGroup == 'A' ? PFColors.accent : PFColors.text,
                                      )),
                                      if (winningGroup == 'A')
                                        const Text('WINNER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: PFColors.accent)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setSheetState(() => winningGroup = winningGroup == 'B' ? '' : 'B'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: winningGroup == 'B' ? Colors.orange.withValues(alpha: 0.2) : PFColors.card,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: winningGroup == 'B' ? Colors.orange : PFColors.border, width: winningGroup == 'B' ? 2 : 1),
                                  ),
                                  child: Column(
                                    children: [
                                      Text('Team B (${teamB.length})', style: TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w700,
                                        color: winningGroup == 'B' ? Colors.orange : PFColors.text,
                                      )),
                                      if (winningGroup == 'B')
                                        const Text('WINNER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.orange)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () => setSheetState(() => winningGroup = ''),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: winningGroup == '' ? PFColors.cardSoft : PFColors.card,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: winningGroup == '' ? PFColors.accent : PFColors.border),
                                ),
                                child: const Text('Draw', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: scoreController,
                                style: const TextStyle(color: PFColors.text, fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: 'Score (e.g. 3-2)',
                                  hintStyle: const TextStyle(color: PFColors.muted, fontSize: 13),
                                  filled: true,
                                  fillColor: PFColors.card,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Select Winner', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            ...List.generate(_players.length, (i) {
                              final p = _players[i];
                              final selected = (winningGroup == p['user_id'].toString());
                              final name = (p['name'] ?? 'Player').toString();
                              return GestureDetector(
                                onTap: () => setSheetState(() => winningGroup = p['user_id'].toString()),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: selected ? PFColors.accent.withValues(alpha: 0.15) : PFColors.card,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: selected ? PFColors.accent : PFColors.border),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                      const Spacer(),
                                      if (selected)
                                        const Icon(Icons.check_circle_rounded, color: PFColors.accent, size: 20),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () => setSheetState(() => winningGroup = 'draw'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: winningGroup == 'draw' ? PFColors.cardSoft : PFColors.card,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: winningGroup == 'draw' ? PFColors.accent : PFColors.border),
                                ),
                                child: Row(
                                  children: [
                                    const Text('Draw', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                    const Spacer(),
                                    if (winningGroup == 'draw')
                                      const Icon(Icons.check_circle_rounded, color: PFColors.accent, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          if (_isTeamSport) ...[
                            if (teamA.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text('Team A', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: PFColors.accent)),
                              ...teamA.map((p) => _buildPlayerRow(p, 'A')),
                            ],
                            if (teamB.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text('Team B', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.orange)),
                              ...teamB.map((p) => _buildPlayerRow(p, 'B')),
                            ],
                            if (unassigned.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Text('Unassigned', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: PFColors.muted)),
                              ...unassigned.map((p) => _buildPlayerRow(p, '')),
                            ],
                          ],
                          if (_isTeamSport && (teamA.isEmpty || teamB.isEmpty))
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Text('Assign at least one player to each team.', style: TextStyle(color: PFColors.muted, fontSize: 13)),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      child: PFButton(
                        label: 'Submit Result',
                        onTap: () async {
                          if (_isTeamSport && (teamA.isEmpty || teamB.isEmpty)) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assign players to both teams')));
                            return;
                          }
                          if (!_isTeamSport && winningGroup.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a winner or draw')));
                            return;
                          }
                          final token = widget.session.token;
                          if (token == null) return;

                          Map<String, List<int>>? teamGroups;
                          int? winnerUserId;
                          String? wg;

                          if (_isTeamSport) {
                            teamGroups = {
                              'A': teamA.map((p) => p['user_id'] as int).toList(),
                              'B': teamB.map((p) => p['user_id'] as int).toList(),
                            };
                            wg = winningGroup.isEmpty ? null : winningGroup;
                          } else {
                            if (winningGroup == 'draw') {
                              wg = '';
                            } else {
                              winnerUserId = int.tryParse(winningGroup);
                            }
                          }

                          final res = await widget.repo.submitMatchResult(
                            token: token,
                            matchId: widget.matchId,
                            matchType: _isTeamSport ? 'pickup' : 'pickup',
                            resultType: winningGroup == 'draw' || winningGroup == '' ? 'draw' : 'individual',
                            winnerUserId: winnerUserId,
                            winningGroup: wg,
                            score: scoreController.text,
                            teamGroups: teamGroups,
                          );

                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(res['message'] ?? (res['success'] == true ? 'Result submitted!' : res['error'] ?? 'Failed')),
                          ));
                          _load();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PFScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Match Details'),
        actions: [IconButton(onPressed: () => Navigator.pushNamed(context, AppRoutes.chat, arguments: {'matchId': widget.matchId, 'title': 'Match Chat'}), icon: const Icon(Icons.chat_bubble_outline_rounded))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PFColors.accent))
          : _match == null
              ? const Center(child: Text('Match not found', style: TextStyle(color: PFColors.muted)))
              : ListView(
                  padding: const EdgeInsets.only(top: 4, bottom: 100),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 14),
                    _buildInfoCards(),
                    const SizedBox(height: 14),
                    _buildPlayersCard(),
                  ],
                ),
      bottomNavigationBar: _match != null ? _buildBottomBar() : null,
    );
  }

  Widget _buildHeader() {
    final sport = _match?['sport']?.toString() ?? 'Sport';
    final title = _match?['title']?.toString() ?? 'Match';
    final dateTimeStr = _match?['date_time']?.toString() ?? '';
    final location = _match?['location']?.toString() ?? '';

    final sportIcon = _sportIcon(sport);
    final gradientColors = _sportGradient(sport);

    return PFCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(sportIcon, size: 16, color: PFColors.accent),
                          const SizedBox(width: 6),
                          Text(sport.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: PFColors.accent, letterSpacing: 1.2)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    _buildStatusBadge(),
                  ],
                ),
                const SizedBox(height: 20),
                Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, height: 1.1)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 14, color: PFColors.muted),
                    const SizedBox(width: 6),
                    Text(_formatDate(dateTimeStr), style: const TextStyle(fontSize: 13, color: PFColors.muted)),
                    const SizedBox(width: 18),
                    const Icon(Icons.location_on_rounded, size: 14, color: PFColors.muted),
                    const SizedBox(width: 6),
                    Flexible(child: Text(location, style: const TextStyle(fontSize: 13, color: PFColors.muted), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    final max = _match?['max_players'] ?? 10;
    final current = _match?['current_players'] ?? 0;
    final spots = _match?['spots_left'] ?? (max - current);
    final isFull = spots <= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isFull ? Colors.red.withValues(alpha: 0.2) : PFColors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: isFull ? Colors.red.withValues(alpha: 0.4) : PFColors.accent.withValues(alpha: 0.3)),
      ),
      child: Text(
        isFull ? 'FULL' : '$spots SPOTS LEFT',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: isFull ? Colors.red : PFColors.accent,
        ),
      ),
    );
  }

  Widget _buildInfoCards() {
    final max = _match?['max_players'] ?? 10;
    final current = _match?['current_players'] ?? 0;
    final spots = _match?['spots_left'] ?? (max - current);
    final price = _match?['price'] ?? 0;
    final description = _match?['description']?.toString() ?? '';
    final organizer = _match?['organizer_name']?.toString() ?? 'Host';

    final ratio = max > 0 ? current / max : 0.0;

    return Column(
      children: [
        PFCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Players', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: PFColors.muted)),
                        const SizedBox(height: 6),
                        Text('$current / $max', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: ratio.clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: PFColors.border,
                            valueColor: AlwaysStoppedAnimation(ratio >= 1 ? Colors.red : PFColors.accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Price', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: PFColors.muted)),
                      const SizedBox(height: 6),
                      Text(
                        price is num && price == 0 ? 'Free' : 'Br $price',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: PFColors.accent),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${spots > 0 ? spots : 0} left',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: spots > 0 ? PFColors.accent : Colors.red),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 10),
          PFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: PFColors.muted)),
                const SizedBox(height: 8),
                Text(description, style: const TextStyle(fontSize: 14, height: 1.5, color: PFColors.text)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        PFCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: PFColors.accent.withValues(alpha: 0.15),
                child: Text(organizer.isNotEmpty ? organizer[0].toUpperCase() : '?', style: const TextStyle(fontWeight: FontWeight.w800, color: PFColors.accent)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Organized by', style: TextStyle(fontSize: 11, color: PFColors.muted)),
                    Text(organizer, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Icon(Icons.verified_rounded, size: 18, color: PFColors.accent.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlayersCard() {
    return PFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Participants (${_players.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
              if (_players.isNotEmpty)
                Text('${_players.length} joined', style: const TextStyle(fontSize: 12, color: PFColors.accent)),
            ],
          ),
          const SizedBox(height: 14),
          if (_players.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No participants yet. Be the first to join!', style: TextStyle(color: PFColors.muted))),
            )
            else
            ...List.generate(_players.length, (i) {
              final p = _players[i];
              final name = (p['name'] ?? 'Player').toString();
              final isOrganizer = p['is_organizer'] == true || p['role'] == 'organizer';
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: i < _players.length - 1 ? Border(bottom: BorderSide(color: PFColors.border.withValues(alpha: 0.4))) : null,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: isOrganizer ? PFColors.accent.withValues(alpha: 0.2) : PFColors.cardSoft,
                      child: Text(name[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: isOrganizer ? PFColors.accent : PFColors.muted)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              if (isOrganizedByCurrentUser(p)) ...[
                                const SizedBox(width: 6),
                                const Text('(You)', style: TextStyle(fontSize: 12, color: PFColors.accent)),
                              ],
                            ],
                          ),
                          if (isOrganizer)
                            const Text('Organizer', style: TextStyle(fontSize: 11, color: PFColors.accent)),
                        ],
                      ),
                    ),
                    if (isOrganizer)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: PFColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text('HOST', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: PFColors.accent, letterSpacing: 0.8)),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final max = _match?['max_players'] ?? 10;
    final current = _match?['current_players'] ?? 0;
    final spots = _match?['spots_left'] ?? (max - current);
    final price = _match?['price'] ?? 0;
    final isFull = spots <= 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [PFColors.background.withValues(alpha: 0), PFColors.background],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    price is num && price == 0 ? 'Free Entry' : 'Br ${price}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: PFColors.accent),
                  ),
                  Text(
                    isFull ? 'No spots available' : '$spots spot${spots == 1 ? '' : 's'} left',
                    style: TextStyle(fontSize: 12, color: isFull ? Colors.red : PFColors.muted),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: _isOrganizer
                  ? PFButton(
                      label: 'Submit Result',
                      onTap: _showSubmitResultSheet,
                    )
                  : PFButton(
                      label: isFull ? 'Join Waitlist' : 'Join Match',
                      onTap: isFull ? () {} : _join,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String dateTimeStr) {
    final dt = DateTime.tryParse(dateTimeStr);
    if (dt == null) return dateTimeStr;
    final now = DateTime.now();
    final diff = dt.difference(now);
    if (diff.inDays == 0) return 'Today, ${_formatTime(dt)}';
    if (diff.inDays == 1) return 'Tomorrow, ${_formatTime(dt)}';
    return '${dt.day}/${dt.month}/${dt.year}, ${_formatTime(dt)}';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${dt.minute.toString().padLeft(2, '0')} $period';
  }

  bool isOrganizedByCurrentUser(Map<String, dynamic> p) {
    return p['is_current_user'] == true;
  }

  IconData _sportIcon(String sport) {
    final s = sport.toLowerCase();
    if (s.contains('soccer') || s.contains('football')) return Icons.sports_soccer_rounded;
    if (s.contains('basketball')) return Icons.sports_basketball_rounded;
    if (s.contains('tennis')) return Icons.sports_tennis_rounded;
    if (s.contains('volleyball')) return Icons.sports_volleyball_rounded;
    if (s.contains('baseball')) return Icons.sports_baseball_rounded;
    return Icons.sports_rounded;
  }

  List<Color> _sportGradient(String sport) {
    final s = sport.toLowerCase();
    if (s.contains('soccer') || s.contains('football')) return const [Color(0xFF1A3A1A), Color(0xFF0D1F0D)];
    if (s.contains('basketball')) return const [Color(0xFF3A1A1A), Color(0xFF1F0D0D)];
    if (s.contains('tennis')) return const [Color(0xFF2A3A1A), Color(0xFF141F0D)];
    return const [Color(0xFF1A2A3A), Color(0xFF0D141F)];
  }
}
