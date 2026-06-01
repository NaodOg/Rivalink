import 'package:flutter/material.dart';

import '../../core/theme/playfair_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/data/models/match.dart';
import 'pf_card.dart';

class MatchCard extends StatelessWidget {
  final PlayFairMatch match;
  final VoidCallback? onTap;

  const MatchCard({super.key, required this.match, this.onTap});

  @override
  Widget build(BuildContext context) {
    return PFCard(
      onTap: onTap,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/images/hero_soccer.jpg',
              width: 72,
              height: 72,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(match.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(prettyDate(match.dateTime), style: const TextStyle(color: PFColors.muted, fontSize: 12)),
                const SizedBox(height: 2),
                Text(match.location, style: const TextStyle(color: PFColors.muted, fontSize: 12)),
              ],
            ),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(child: Text(br(match.price), style: const TextStyle(color: PFColors.accent, fontWeight: FontWeight.w700))),
                const SizedBox(height: 6),
                Text('${match.currentPlayers}/${match.maxPlayers}', style: const TextStyle(color: PFColors.muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
