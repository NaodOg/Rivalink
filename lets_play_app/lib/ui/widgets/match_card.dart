import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/sport_utils.dart';
import '../../core/data/models/match.dart';
import 'pf_badge.dart';
import 'pf_card.dart';

class MatchCard extends StatelessWidget {
  final RivalinkMatch match;
  final VoidCallback? onTap;

  const MatchCard({super.key, required this.match, this.onTap});

  @override
  Widget build(BuildContext context) {
    final full = match.currentPlayers >= match.maxPlayers;
    return PFCard(
      onTap: onTap,
      child: Row(
        children: [
          _SportTile(sport: match.sport),
          const SizedBox(width: PFSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                match.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
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
                  if (match.skillLevel != 'any') ...[
                    const SizedBox(width: 8),
                    PFBadge(
                      label: match.skillLevel[0].toUpperCase() + match.skillLevel.substring(1),
                      color: PFColors.secondary,
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
                br(match.price),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PFColors.primary, fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: full ? PFColors.danger.withValues(alpha: 0.15) : PFColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(PFRadius.pill),
                ),
                child: Text(
                  full ? 'Full' : '${match.currentPlayers}/${match.maxPlayers}',
                  style: TextStyle(
                    color: full ? PFColors.danger : PFColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SportTile extends StatelessWidget {
  final String sport;
  const _SportTile({required this.sport});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: PFColors.surfaceRaised,
        borderRadius: BorderRadius.circular(PFRadius.md),
        border: Border.all(color: PFColors.border),
      ),
      alignment: Alignment.center,
      child: Icon(sportIcon(sport), color: PFColors.primary, size: 28),
    );
  }
}
