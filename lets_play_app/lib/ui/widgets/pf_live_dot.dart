import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';

/// Small pulsing dot used for LIVE indicators.
class PFLiveDot extends StatefulWidget {
  final Color color;
  final double size;
  const PFLiveDot({super.key, this.color = PFColors.success, this.size = 8});

  @override
  State<PFLiveDot> createState() => _PFLiveDotState();
}

class _PFLiveDotState extends State<PFLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(
          CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
