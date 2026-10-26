import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/sport_utils.dart';
import '../../core/data/models/match.dart';
import 'pf_card.dart';

class MatchCard extends StatelessWidget {
  final RivalinkMatch match;
  final VoidCallback? onTap;

  const MatchCard({super.key, required this.match, this.onTap});

  @override
  Widget build(BuildContext context) {
    final full = match.currentPlayers >= match.maxPlayers;
    final startsIn = match.dateTime.difference(DateTime.now());
    final urgent = !full && startsIn.inHours < 24 && startsIn.inMinutes > 0;
    final scarce = !full && match.spotsLeft <= 3 && match.spotsLeft > 0;
    final sportColor = PFSport.color(match.sport);

    return PFCard(
      onTap: onTap,
      child: Row(
        children: [
          _SportTile(sport: match.sport, color: sportColor),
          const SizedBox(width: PFSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        match.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                    if (match.outcome != null) ...[
                      const SizedBox(width: 6),
                      _OutcomeBadge(outcome: match.outcome!),
                    ],
                  ],
                ),
                if (match.reason != null && match.reason!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 11, color: PFColors.secondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          match.reason!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: PFColors.secondary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        prettyDate(match.dateTime),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: PFColors.textSecondary, fontSize: 12),
                      ),
                    ),
                    if (urgent) ...[
                      const SizedBox(width: 8),
                      _Chip(
                        label: startsIn.inHours < 1
                            ? 'Starts soon'
                            : 'Starts in ${startsIn.inHours}h',
                        color: PFColors.warning,
                      ),
                    ] else if (match.skillLevel != 'any') ...[
                      const SizedBox(width: 8),
                      _Chip(
                        label: match.skillLevel[0].toUpperCase() +
                            match.skillLevel.substring(1),
                        color: _skillColor(match.skillLevel),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 13, color: PFColors.textTertiary),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        match.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: PFColors.textSecondary, fontSize: 12),
                      ),
                    ),
                    if (match.currentPlayers > 0) ...[
                      const SizedBox(width: 8),
                      _AvatarStack(
                        names: match.participantsPreview,
                        count: match.currentPlayers,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: PFSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                match.price == 0 ? 'Free' : br(match.price),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: match.price == 0 ? PFColors.success : PFColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              _Chip(
                label: full
                    ? 'Waitlist'
                    : (scarce ? 'Only ${match.spotsLeft} left' : '${match.currentPlayers}/${match.maxPlayers}'),
                color: full
                    ? PFColors.danger
                    : (scarce ? PFColors.warning : PFColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _skillColor(String skill) {
    switch (skill) {
      case 'beginner':
        return PFColors.success;
      case 'intermediate':
        return PFColors.secondary;
      case 'advanced':
        return PFColors.warning;
      default:
        return PFColors.secondary;
    }
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(PFRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _OutcomeBadge extends StatelessWidget {
  final String outcome;
  const _OutcomeBadge({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (outcome) {
      'win' => ('W', PFColors.success),
      'loss' => ('L', PFColors.danger),
      _ => ('D', PFColors.textSecondary),
    };
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  final List<String> names;
  final int count;
  const _AvatarStack({required this.names, required this.count});

  @override
  Widget build(BuildContext context) {
    final shown = names.take(3).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 0),
            child: Align(
              widthFactor: 0.68,
              child: Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: PFColors.surfaceHigh,
                  shape: BoxShape.circle,
                  border: Border.all(color: PFColors.background, width: 1.5),
                ),
                child: Text(
                  shown[i].trim().isEmpty ? '?' : shown[i].trim()[0].toUpperCase(),
                  style: const TextStyle(
                      fontSize: 8.5, fontWeight: FontWeight.w700, color: PFColors.textSecondary),
                ),
              ),
            ),
          ),
        const SizedBox(width: 4),
        Text(
          '$count going',
          style: const TextStyle(color: PFColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

class _SportTile extends StatelessWidget {
  final String sport;
  final Color color;
  const _SportTile({required this.sport, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(PFRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: Icon(sportIcon(sport), color: color, size: 28),
    );
  }
}
