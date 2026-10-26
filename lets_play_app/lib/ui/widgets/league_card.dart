import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';
import 'pf_card.dart';
import 'pf_live_dot.dart';

class LeagueCard extends StatelessWidget {
  final Map<String, dynamic> league;
  final VoidCallback? onTap;

  const LeagueCard({super.key, required this.league, this.onTap});

  String get _status => league['status']?.toString() ?? 'registration';

  @override
  Widget build(BuildContext context) {
    final sport = league['sport']?.toString() ?? 'other';
    final sportColor = PFSport.color(sport);
    final current = (league['current_teams'] ?? 0) as int;
    final max = (league['max_teams'] ?? 8) as int;
    final prize = league['prize']?.toString() ?? '';
    final entryFee = league['entry_fee']?.toString() ?? '0';
    final teamNames =
        List<String>.from(league['team_names'] as List<dynamic>? ?? const []);
    final closes = _closesLabel();
    final remaining = max - current;

    return PFCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: sportColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(PFRadius.md),
                  border: Border.all(color: sportColor.withValues(alpha: 0.35)),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.emoji_events_rounded, color: sportColor),
              ),
              const SizedBox(width: PFSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (league['name'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _statusChip(closes),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${league['format'] ?? 'League'} • $current/$max teams'
                      '${closes == null && _status == 'registration' ? ' • Open' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: PFColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _Initials(teamNames: teamNames),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _teamsLabel(teamNames, current),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: PFColors.textSecondary, fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: PFSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (prize.isNotEmpty) ...[
                    const Text('PRIZE',
                        style: TextStyle(
                            fontSize: 9.5,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w700,
                            color: PFColors.textTertiary)),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: 84,
                      child: Text(
                        prize,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: PFColors.gold,
                            fontWeight: FontWeight.w800,
                            fontSize: 14),
                      ),
                    ),
                  ] else if (_status == 'completed' &&
                      league['champion_team_name'] != null) ...[
                    const Icon(Icons.emoji_events_rounded,
                        size: 18, color: PFColors.gold),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: 84,
                      child: Text(
                        league['champion_team_name'].toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: PFColors.gold,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: entryFee == '0'
                          ? PFColors.success.withValues(alpha: 0.14)
                          : PFColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(PFRadius.pill),
                    ),
                    child: Text(
                      entryFee == '0' || entryFee == '0.00'
                          ? 'Free entry'
                          : 'Br $entryFee',
                      style: TextStyle(
                        color: entryFee == '0' || entryFee == '0.00'
                            ? PFColors.success
                            : PFColors.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (max > 0 &&
              (_status == 'registration' || _status == 'live')) ...[
            const SizedBox(height: PFSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(PFRadius.pill),
              child: LinearProgressIndicator(
                value: max == 0 ? 0 : (current / max).clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: PFColors.surfaceHigh,
                valueColor: AlwaysStoppedAnimation(
                  remaining <= 2 ? PFColors.warning : sportColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _teamsLabel(List<String> names, int current) {
    if (current == 0) return 'No teams yet — be the first';
    if (names.isEmpty) return '$current teams joined';
    return '$current teams joined';
  }

  String? _closesLabel() {
    if (_status != 'registration') return null;
    final start = DateTime.tryParse(league['start_date']?.toString() ?? '')?.toLocal();
    if (start == null) return null;
    final diff = start.difference(DateTime.now());
    if (diff.isNegative) return null;
    if (diff.inDays >= 1 && diff.inDays <= 3) return 'Closes in ${diff.inDays}d';
    if (diff.inDays < 1) return 'Closes today';
    return null;
  }

  Widget _statusChip(String? closes) {
    if (_status == 'live') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PFLiveDot(color: PFColors.success, size: 7),
          const SizedBox(width: 5),
          Text('LIVE',
              style: TextStyle(
                  color: PFColors.success,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4)),
        ],
      );
    }
    final (label, color) = switch (_status) {
      'completed' => ('Completed', PFColors.textTertiary),
      'cancelled' => ('Cancelled', PFColors.danger),
      _ => closes != null
          ? (closes.toUpperCase(), PFColors.warning)
          : ('OPEN', PFColors.secondary),
    };
    return Text(
      label,
      style: TextStyle(
          color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4),
    );
  }
}

class _Initials extends StatelessWidget {
  final List<String> teamNames;
  const _Initials({required this.teamNames});

  @override
  Widget build(BuildContext context) {
    final shown = teamNames.take(3).toList();
    if (shown.isEmpty) {
      return const Icon(Icons.groups_rounded, size: 14, color: PFColors.textTertiary);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++)
          Align(
            widthFactor: 0.7,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: PFColors.surfaceHigh,
                shape: BoxShape.circle,
                border: Border.all(color: PFColors.background, width: 1.2),
              ),
              child: Text(
                shown[i].trim().isEmpty
                    ? '?'
                    : shown[i].trim()[0].toUpperCase(),
                style: const TextStyle(
                    fontSize: 7.5,
                    fontWeight: FontWeight.w700,
                    color: PFColors.textSecondary),
              ),
            ),
          ),
      ],
    );
  }
}
