import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';
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
    return Row(
      children: [
        PFSportTile(sport: sport, size: 40),
        const SizedBox(width: PFSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text('$played played · $wins/$losses/$draws',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
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
