import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';
import 'pf_card.dart';

class LeagueCard extends StatelessWidget {
  final Map<String, dynamic> league;
  final VoidCallback? onTap;

  const LeagueCard({super.key, required this.league, this.onTap});

  @override
  Widget build(BuildContext context) {
    return PFCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: PFColors.surfaceRaised,
              borderRadius: BorderRadius.circular(PFRadius.md),
              border: Border.all(color: PFColors.border),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.emoji_events_rounded, color: PFColors.primary),
          ),
          const SizedBox(width: PFSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((league['name'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  '${league['format'] ?? 'League'} • ${league['current_teams'] ?? league['teams'] ?? 0} teams',
                  style: const TextStyle(color: PFColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: PFSpacing.sm),
          Text(
            (league['status'] ?? league['status_display'] ?? '').toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: PFColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
