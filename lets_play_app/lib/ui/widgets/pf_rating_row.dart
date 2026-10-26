import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';
import 'pf_badge.dart';
import 'pf_sport_tile.dart';

class PFRatingRow extends StatelessWidget {
  final String sport;
  final int elo;
  final int wins;
  final int losses;
  final int draws;
  final int played;

  const PFRatingRow({
    super.key,
    required this.sport,
    required this.elo,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.played,
  });

  @override
  Widget build(BuildContext context) {
    final name = sport.isEmpty ? 'Sport' : sport[0].toUpperCase() + sport.substring(1);
    final tier = pfEloTier(elo);
    final progress = pfEloProgress(elo);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PFSportTile(sport: sport, size: 40),
        const SizedBox(width: PFSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  const SizedBox(width: 6),
                  PFBadge(label: tier.label, color: tier.color),
                ],
              ),
              const SizedBox(height: 3),
              Text('$played played · $wins/$losses/$draws',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(PFRadius.pill),
                child: LinearProgressIndicator(
                  value: progress.fraction.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: PFColors.surfaceHigh,
                  valueColor: AlwaysStoppedAnimation(tier.color),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                progress.remaining > 0
                    ? '${progress.remaining} pts to ${progress.nextLabel}'
                    : 'Top tier — keep defending it',
                style: const TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 0.3,
                    fontWeight: FontWeight.w600,
                    color: PFColors.textTertiary),
              ),
            ],
          ),
        ),
        const SizedBox(width: PFSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('$elo',
                style: PFType.number.copyWith(fontSize: 18, color: PFColors.primary)),
            Text('ELO', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}
