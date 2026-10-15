import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';

/// Rounded category tile keyed to the sport's identity color.
class PFSportTile extends StatelessWidget {
  final String sport;
  final double size;
  final bool solid;

  const PFSportTile({super.key, required this.sport, this.size = 56, this.solid = false});

  @override
  Widget build(BuildContext context) {
    final color = PFSport.color(sport);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(PFRadius.lg),
        border: Border.all(color: color.withValues(alpha: solid ? 0 : 0.35)),
      ),
      alignment: Alignment.center,
      child: Icon(
        PFSport.icon(sport),
        color: solid ? PFColors.onPrimary : color,
        size: size * 0.46,
      ),
    );
  }
}
