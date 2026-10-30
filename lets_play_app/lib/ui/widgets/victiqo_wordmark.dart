import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';

/// VICTIQO wordmark: the Q is the brand-blue accent, the rest is white.
class VictiqoWordmark extends StatelessWidget {
  final double fontSize;
  final double letterSpacing;
  final FontWeight fontWeight;
  final Color baseColor;
  final Color qColor;

  const VictiqoWordmark({
    super.key,
    this.fontSize = 28,
    this.letterSpacing = 3.9,
    this.fontWeight = FontWeight.w700,
    this.baseColor = Colors.white,
    this.qColor = PFColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: PFType.brand,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: baseColor,
      height: 1,
    );
    return RichText(
      text: TextSpan(
        style: style,
        children: [
          const TextSpan(text: 'VICTI'),
          TextSpan(text: 'Q', style: TextStyle(color: qColor)),
          const TextSpan(text: 'O'),
        ],
      ),
      textScaler: MediaQuery.textScalerOf(context),
    );
  }
}
