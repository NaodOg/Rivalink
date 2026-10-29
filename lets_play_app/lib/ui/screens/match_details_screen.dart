import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/services/analytics_service.dart';
import 'package:flutter/services.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../../core/utils/formatters.dart';
import '../widgets/pf_avatar.dart';
import '../widgets/pf_badge.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_section_header.dart';

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
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() { _loading = true; _error = false; });
    try {
      final details = await widget.repo.getMatchDetails(token, widget.matchId);
      if (!mounted) return;
      setState(() {
        _match = details['match'] as Map<String, dynamic>?;
        _players = List<dynamic>.from(details['participants'] ?? []);
        _loading = false;
        final loaded = _match;
        if (loaded != null) {
          AnalyticsService.event('match_viewed', {
            'match_id': widget.matchId,
            'sport': loaded['sport']?.toString() ?? '',
            'price': loaded['price']?.toString() ?? '',
            'current_players': loaded['current_players'] ?? 0,
          });
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = true; });
    }
  }

  Future<void> _join() async {
    final token = widget.session.token;
    if (token == null) return;
    AnalyticsService.event('match_join_clicked', {
      'match_id': widget.matchId,
      'sport': _match?['sport']?.toString() ?? '',
      'price': _match?['price']?.toString() ?? '',
    });
    try {
      final res = await widget.repo.joinMatch(token, widget.matchId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((res['message'] ?? res['error'] ?? '').toString())));
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to join match.')));
    }
  }

  bool get _isOrganizer {
    final userId = widget.session.user?['id'];
    return _match?['organizer'] == userId || _match?['organizer_id'] == userId;
  }

  bool get _isParticipant => _match?['is_participant'] == true;
  bool get _isBooked => _match?['is_booked'] == true;
  bool get _hasWithdrawn => _match?['has_withdrawn'] == true;
  bool get _canWithdraw => _match?['can_withdraw'] == true;
  bool get _canJoinFunded => _match?['can_join_funded'] == true;
  bool get _hasVenue => _match?['venue_id'] != null;
  String get _bookingStatus => _match?['booking_status']?.toString() ?? 'none';
  String? get _myPaymentStatus => _match?['my_payment_status']?.toString();
  bool get _myBookingConfirmed => _match?['my_booking_confirmed'] == true;
  Map<String, dynamic> get _funding =>
      (_match?['funding'] as Map?)?.cast<String, dynamic>() ?? const {};
  double get _price =>
      double.tryParse(_match?['price']?.toString() ?? '0') ?? 0;

  Future<void> _payShare() async {
    final token = widget.session.token;
    if (token == null) return;
    AnalyticsService.event('match_share_pay_clicked', {
      'match_id': widget.matchId,
      'price': _price,
    });
    final result = await widget.repo.payMatchShare(token, widget.matchId);
    if (!mounted) return;
    final checkout = result['checkout_url']?.toString() ?? '';
    final creditUsed =
        double.tryParse(result['credit_used']?.toString() ?? '0') ?? 0;
    if (checkout.isNotEmpty) {
      final url = Uri.parse(checkout);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    }
    if (!mounted) return;
    final creditNote =
        creditUsed > 0 ? ' Br ${creditUsed.toStringAsFixed(2)} credit applied.' : '';
    final message = result['success'] == true
        ? (checkout.isNotEmpty
            ? 'Complete the payment in your browser, then refresh.$creditNote'
            : 'Share paid — your spot is secured.$creditNote')
        : (result['message'] ?? result['error'] ?? 'Payment failed').toString();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    _load();
  }

  Future<void> _withdraw() async {
    final token = widget.session.token;
    if (token == null) return;
    final isHost = _isOrganizer;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PFColors.surfaceRaised,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PFRadius.lg)),
        title: Text(isHost ? 'Withdraw and hand over?' : 'Withdraw from match?'),
        content: Text(
          isHost
              ? 'You will lose your share and the match will stay booked. '
                  'Another player takes over as organizer.'
              : 'You will lose your share — there is no refund after booking. '
                  'Your spot stays funded so another player can join free.',
          style: const TextStyle(color: PFColors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Withdraw',
                  style: TextStyle(color: PFColors.danger))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final result = await widget.repo.withdrawMatch(token, widget.matchId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['success'] == true
            ? 'You withdrew — your spot is funded for a replacement.'
            : (result['error'] ?? 'Could not withdraw').toString())));
    if (result['success'] == true) _load();
  }

  Future<void> _requestBooking() async {
    final token = widget.session.token;
    if (token == null) return;
    final result =
        await widget.repo.requestVenueBooking(token, widget.matchId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['success'] == true
            ? 'Booking requested — every player must confirm.'
            : (result['error'] ?? 'Could not request booking').toString())));
    if (result['success'] == true) _load();
  }

  Future<void> _confirmBooking() async {
    final token = widget.session.token;
    if (token == null) return;
    final result =
        await widget.repo.confirmVenueBooking(token, widget.matchId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['success'] == true
            ? (result['message'] ?? 'Booking confirmed').toString()
            : (result['error'] ?? 'Could not confirm').toString())));
    if (result['success'] == true) _load();
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
      if (group == 'A') {
        teamA.add(p);
      } else if (group == 'B') {
        teamB.add(p);
      } else {
        unassigned.add(p);
      }
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
                if (group == 'A') {
                  teamA.add(player);
                } else if (group == 'B') {
                  teamB.add(player);
                } else {
                  unassigned.add(player);
                }
              });
            }

            buildPlayerRow(Map<String, dynamic> p, String currentGroup) {
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
                              ? PFColors.secondary.withValues(alpha: 0.25)
                              : PFColors.cardSoft,
                      child: Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    if (currentGroup == 'A')
                      const Icon(Icons.circle, color: PFColors.accent, size: 10)
                    else if (currentGroup == 'B')
                      const Icon(Icons.circle, color: PFColors.secondary, size: 10),
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
                                    color: winningGroup == 'B' ? PFColors.secondary.withValues(alpha: 0.2) : PFColors.card,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: winningGroup == 'B' ? PFColors.secondary : PFColors.border, width: winningGroup == 'B' ? 2 : 1),
                                  ),
                                  child: Column(
                                    children: [
                                      Text('Team B (${teamB.length})', style: TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w700,
                                        color: winningGroup == 'B' ? PFColors.secondary : PFColors.text,
                                      )),
                                      if (winningGroup == 'B')
                                        const Text('WINNER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: PFColors.secondary)),
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
                              ...teamA.map((p) => buildPlayerRow(p, 'A')),
                            ],
                            if (teamB.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text('Team B', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: PFColors.secondary)),
                              ...teamB.map((p) => buildPlayerRow(p, 'B')),
                            ],
                            if (unassigned.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Text('Unassigned', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: PFColors.muted)),
                              ...unassigned.map((p) => buildPlayerRow(p, '')),
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
                          final messenger = ScaffoldMessenger.of(context);
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
                            wg = (winningGroup == 'A' || winningGroup == 'B') ? winningGroup : null;
                          } else {
                            if (winningGroup == 'draw') {
                              wg = '';
                            } else {
                              winnerUserId = int.tryParse(winningGroup);
                            }
                          }

                          final isDraw = winningGroup == 'draw' || winningGroup.isEmpty;
                          final res = await widget.repo.submitMatchResult(
                            token: token,
                            matchId: widget.matchId,
                            matchType: _isTeamSport ? 'team_vs_team' : 'pickup',
                            resultType: isDraw ? 'draw' : (_isTeamSport ? 'team' : 'individual'),
                            winnerUserId: winnerUserId,
                            winningGroup: wg,
                            score: scoreController.text,
                            teamGroups: teamGroups,
                          );

                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          messenger.showSnackBar(SnackBar(
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

  String get _sport => _match?['sport']?.toString() ?? 'sport';
  String get _title => _match?['title']?.toString() ?? 'Match';
  String get _location => _match?['location']?.toString() ?? '';
  String get _description => _match?['description']?.toString() ?? '';
  String get _organizer => _match?['organizer_name']?.toString() ?? 'Host';
  DateTime get _dateTime =>
      DateTime.tryParse(_match?['date_time']?.toString() ?? '') ?? DateTime.now();
  int get _max => (_match?['max_players'] ?? 10) as int;
  int get _current => (_match?['current_players'] ?? 0) as int;
  int get _spots => (_match?['spots_left'] ?? (_max - _current)) as int;

  String get _skill => _match?['skill_level']?.toString() ?? 'any';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PFColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Match chat',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.chat,
                arguments: {'matchId': widget.matchId, 'title': 'Match chat'}),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
          ),
          if (_match != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              color: PFColors.surfaceRaised,
              onSelected: (v) {
                if (v == 'report') _reportHost();
                if (v == 'share') _shareMatch();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'share', child: Text('Share match')),
                if (!_isOrganizer)
                  const PopupMenuItem(value: 'report', child: Text('Report host')),
              ],
            ),
        ],
      ),
      body: _body(),
      bottomNavigationBar: _match != null ? _bottomBar() : null,
    );
  }

  void _shareMatch() {
    final spots = _spots <= 0 ? 'Full' : '$_spots spots left';
    Clipboard.setData(ClipboardData(
      text: '${_sport.toUpperCase()} · $_title\n${prettyDate(_dateTime)} · $_location\n$spots — join on Rivalink!',
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Match details copied — paste to share')),
    );
  }

  Future<void> _reportHost() async {
    final token = widget.session.token;
    final hostId = _match?['organizer_id'];
    if (token == null || hostId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PFColors.surfaceRaised,
        title: const Text('Report host?'),
        content: const Text('This helps keep Rivalink safe. Our team will review it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Report', style: TextStyle(color: PFColors.danger)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final res = await widget.repo.submitReport(
      token: token,
      targetUserId: hostId as int,
      matchId: widget.matchId,
      category: 'abuse',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res['success'] == true ? 'Report submitted' : 'Could not submit report')),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: PFColors.primary));
    }
    if (_error) {
      return Center(
        child: PFEmptyState(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load match",
          message: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: _load,
        ),
      );
    }
    if (_match == null) {
      return const Center(
        child: PFEmptyState(icon: Icons.search_off_rounded, title: 'Match not found'),
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _hero(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _stats(),
              if (_hasVenue) ...[
                const SizedBox(height: PFSpacing.lg),
                _bookingCard(),
              ],
              if (_canWithdraw) ...[
                const SizedBox(height: PFSpacing.lg),
                _withdrawCard(),
              ],
              if (_description.isNotEmpty) ...[
                const SizedBox(height: PFSpacing.lg),
                _descriptionCard(),
              ],
              const SizedBox(height: PFSpacing.lg),
              _organizerCard(),
              const SizedBox(height: PFSpacing.xxl),
              PFSectionHeader(
                eyebrow: 'Roster',
                title: 'Lineup',
                trailing: PFBadge(
                    label: '${_players.length} joined',
                    color: PFColors.textSecondary),
              ),
              const SizedBox(height: PFSpacing.md),
              _lineup(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hero() {
    final color = PFSport.color(_sport);
    final topPad = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.22),
            PFColors.surface,
            PFColors.background,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -34,
            top: topPad - 18,
            child: Icon(
              PFSport.icon(_sport),
              size: 200,
              color: color.withValues(alpha: 0.10),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, topPad + 4, 20, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PFBadge(
                      label: _sport.toUpperCase(),
                      icon: PFSport.icon(_sport),
                      color: color,
                      solid: true,
                    ),
                    if (_skill != 'any') ...[
                      const SizedBox(width: PFSpacing.sm),
                      PFBadge(label: _skill.toUpperCase(), color: PFColors.secondary),
                    ],
                    const Spacer(),
                    _statusBadge(),
                  ],
                ),
                const SizedBox(height: 18),
                Text(_title, style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    _metaChip(Icons.calendar_today_rounded, prettyDate(_dateTime)),
                    if (_location.isNotEmpty) _metaChip(Icons.place_outlined, _location),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: PFColors.textSecondary),
        const SizedBox(width: 6),
        Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }

  Widget _statusBadge() {
    final isFull = _spots <= 0;
    return PFBadge(
      label: isFull ? 'FULL' : '$_spots SPOTS LEFT',
      color: isFull ? PFColors.danger : PFColors.primary,
    );
  }

  Widget _stats() {
    final price = double.tryParse(_match?['price']?.toString() ?? '0') ?? 0;
    final priceText = price == 0 ? 'Free' : 'Br ${price.toStringAsFixed(0)}';
    return PFCard(
      child: Row(
        children: [
          _stat('PLAYERS', '$_current/$_max'),
          _vdiv(),
          _stat('PRICE', priceText, primary: true),
          _vdiv(),
          _stat('SPOTS LEFT', '$_spots', danger: _spots <= 0),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {bool primary = false, bool danger = false}) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          Text(value,
              style: PFType.number.copyWith(
                fontSize: 20,
                color: danger
                    ? PFColors.danger
                    : (primary ? PFColors.primary : PFColors.text),
              )),
        ],
      ),
    );
  }

  Widget _vdiv() => Container(
        width: 1,
        height: 38,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: PFColors.hairline,
      );

  Widget _descriptionCard() {
    return PFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ABOUT', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          Text(_description, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }

  Widget _organizerCard() {
    return PFCard(
      raised: true,
      child: Row(
        children: [
          PFAvatar(name: _organizer, size: 40),
          const SizedBox(width: PFSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Organized by', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 2),
                Text(_organizer, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
          const Icon(Icons.verified_rounded, color: PFColors.primary, size: 18),
        ],
      ),
    );
  }

  Widget _lineup() {
    if (_players.isEmpty) {
      return PFCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('No one has joined yet. Be the first.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }
    return PFCard(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Column(
        children: [
          for (int i = 0; i < _players.length; i++) ...[
            _playerRow(_players[i]),
            if (i < _players.length - 1)
              const Divider(height: 1, indent: 52, color: PFColors.hairline),
          ],
        ],
      ),
    );
  }

  Widget _playerRow(Map<String, dynamic> p) {
    final name = (p['name'] ?? 'Player').toString();
    final isHost = p['is_organizer'] == true;
    final isMe = p['id'] == widget.session.user?['id'];
    final withdrawn = p['withdrawn'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          PFAvatar(name: name, size: 38),
          const SizedBox(width: PFSpacing.md),
          Expanded(
            child: Text(name,
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis),
          ),
          if (withdrawn) ...[
            const PFBadge(label: 'WITHDREW', color: PFColors.danger),
            const SizedBox(width: 6),
          ],
          if (isMe) ...[
            const PFBadge(label: 'YOU', color: PFColors.secondary),
            const SizedBox(width: 6),
          ],
          if (isHost) const PFBadge(label: 'HOST', color: PFColors.primary),
        ],
      ),
    );
  }

  Widget _bookingCard() {
    final target = double.tryParse(_funding['target']?.toString() ?? '0') ?? 0;
    final collected =
        double.tryParse(_funding['collected']?.toString() ?? '0') ?? 0;
    final fee = double.tryParse(_funding['service_fee']?.toString() ?? '0') ?? 0;
    final openSpots = (_funding['open_funded_spots'] ?? 0) as int;
    final status = _bookingStatus;
    final (label, color) = switch (status) {
      'confirmed' => ('BOOKED', PFColors.success),
      'requested' => ('AWAITING CONFIRMATION', PFColors.warning),
      'cancelled' => ('CANCELLED', PFColors.danger),
      _ => ('COLLECTING', PFColors.primary),
    };
    final progress = target > 0 ? (collected / target).clamp(0.0, 1.0) : 1.0;
    final canRequest = _isOrganizer && status != 'confirmed' && status != 'requested';
    final canConfirm = !_isOrganizer &&
        _isParticipant &&
        status == 'requested' &&
        !_myBookingConfirmed &&
        !_hasWithdrawn;

    return PFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.stadium_outlined,
                  size: 18, color: PFColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Field booking',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              PFBadge(label: label, color: color),
            ],
          ),
          const SizedBox(height: 8),
          if (target > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(PFRadius.pill),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: PFColors.surfaceHigh,
                valueColor:
                    AlwaysStoppedAnimation<Color>(status == 'confirmed'
                        ? PFColors.success
                        : PFColors.primary),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Br ${collected.toStringAsFixed(0)} of '
              'Br ${target.toStringAsFixed(0)} collected'
              '${_funding['open_funded_spots'] != null && openSpots > 0 ? ' · $openSpots funded spot${openSpots == 1 ? '' : 's'} open' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            fee > 0
                ? 'Field Br ${_funding['venue_amount'] ?? '0'} + '
                    'Rivalink fee Br ${fee.toStringAsFixed(0)}'
                : 'Free field — no service fee',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (status == 'confirmed')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'The venue is paid. Any surplus is held until kickoff to fund withdrawals.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (canRequest) ...[
            const SizedBox(height: PFSpacing.md),
            PFButton(
              label: 'Request field booking',
              variant: PFButtonVariant.secondary,
              dense: true,
              icon: Icons.event_available_outlined,
              onTap: _requestBooking,
            ),
          ],
          if (status == 'requested' && _isOrganizer)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Waiting for every player to confirm before booking.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (canConfirm) ...[
            const SizedBox(height: PFSpacing.md),
            PFButton(
              label: 'Confirm booking',
              dense: true,
              icon: Icons.check_circle_outline_rounded,
              onTap: _confirmBooking,
            ),
            const SizedBox(height: 4),
            Text(
              'After booking your share is non-refundable unless the host or venue cancels.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _withdrawCard() {
    return PFCard(
      color: PFColors.warning.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.exit_to_app_rounded,
                  size: 18, color: PFColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isOrganizer ? 'Hand over the match' : "Can't make it?",
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _isOrganizer
                ? 'Withdrawing forfeits your share. Another player becomes organizer and the match stays booked.'
                : 'Withdrawing forfeits your share — no refund after booking. '
                    'Your spot stays funded so a replacement can join free.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: PFSpacing.md),
          PFButton(
            label: _isOrganizer
                ? 'Withdraw and hand over'
                : 'Withdraw from match',
            variant: PFButtonVariant.secondary,
            dense: true,
            onTap: _withdraw,
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final priceText = _price == 0 ? 'Free' : 'Br ${_price.toStringAsFixed(0)}';
    final isFull = _spots <= 0;
    final paidIn = const ['held', 'released', 'covered']
        .contains(_myPaymentStatus);
    final canPay = _isParticipant &&
        !_isBooked &&
        !_hasWithdrawn &&
        !paidIn &&
        _price > 0;
    final fundedSpots = (_funding['open_funded_spots'] ?? 0) as int;

    Widget action;
    if (canPay) {
      action = PFButton(
        label: 'Pay my share',
        icon: Icons.lock_outline_rounded,
        onTap: _payShare,
      );
    } else if (_isBooked) {
      if (_isOrganizer) {
        action = PFButton(
          label: 'Submit result',
          icon: Icons.emoji_events_outlined,
          onTap: _showSubmitResultSheet,
        );
      } else if (_isParticipant) {
        action = PFButton(
          label: _hasWithdrawn ? 'Withdrawn' : 'You are in',
          onTap: null,
        );
      } else if (_canJoinFunded) {
        action = PFButton(
          label: 'Join free (funded spot)',
          icon: Icons.card_giftcard_rounded,
          onTap: _join,
        );
      } else {
        action = PFButton(label: 'Field booked', onTap: null);
      }
    } else if (_isOrganizer) {
      action = PFButton(
        label: 'Submit result',
        icon: Icons.emoji_events_outlined,
        onTap: _showSubmitResultSheet,
      );
    } else if (_isParticipant) {
      action = PFButton(label: 'You are in', onTap: null);
    } else {
      action = PFButton(
        label: isFull ? 'Waitlist' : 'Join match',
        icon: isFull ? null : Icons.add_rounded,
        onTap: isFull ? null : _join,
      );
    }

    final subtitle = _isBooked
        ? (fundedSpots > 0
            ? '$fundedSpots funded spot${fundedSpots == 1 ? '' : 's'} available'
            : 'Field booked · no refunds after booking')
        : (isFull
            ? 'No spots available'
            : '$_spots spot${_spots == 1 ? '' : 's'} left');

    return Container(
      decoration: const BoxDecoration(
        color: PFColors.surface,
        border: Border(top: BorderSide(color: PFColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(priceText,
                      style: PFType.number.copyWith(
                          fontSize: 20, color: PFColors.primary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              const SizedBox(width: PFSpacing.lg),
              Expanded(child: action),
            ],
          ),
        ),
      ),
    );
  }
}
