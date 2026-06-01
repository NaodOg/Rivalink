import 'package:flutter/material.dart';

import '../../core/theme/playfair_theme.dart';
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
              borderRadius: BorderRadius.circular(13),
              gradient: const LinearGradient(colors: [Color(0xFF2D372D), Color(0xFF1B231B)]),
            ),
            child: const Icon(Icons.emoji_events_rounded, color: PFColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((league['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${league['format'] ?? 'League'} • ${league['current_teams'] ?? league['teams'] ?? 0} teams', style: const TextStyle(color: PFColors.muted, fontSize: 12)),
              ],
            ),
          ),
          Flexible(
            child: Text(
              (league['status'] ?? league['status_display'] ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PFColors.accent, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
