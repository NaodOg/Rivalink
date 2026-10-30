import 'package:flutter/material.dart';

import 'victiqo_wordmark.dart';

/// VICTIQO brand lockup: the pin+trophy mark plus the wordmark.
class PFLogo extends StatelessWidget {
  final double markSize;
  final bool showWordmark;
  final double wordSize;
  final bool vertical;
  final Color? wordColor;

  const PFLogo({
    super.key,
    this.markSize = 44,
    this.showWordmark = true,
    this.wordSize = 28,
    this.vertical = false,
    this.wordColor,
  });

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      'assets/images/rivalink_pin.png',
      height: markSize,
      filterQuality: FilterQuality.high,
    );
    if (!showWordmark) return mark;
    final word = VictiqoWordmark(
      fontSize: wordSize,
      letterSpacing: wordSize * 0.14,
      baseColor: wordColor ?? Colors.white,
    );
    if (vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          SizedBox(height: markSize * 0.18),
          word,
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: markSize * 0.30),
        word,
      ],
    );
  }
}
