import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';

class PFCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool raised;
  final Color? color;
  final EdgeInsetsGeometry? margin;
  final double radius;

  const PFCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.raised = false,
    this.color,
    this.margin,
    this.radius = PFRadius.lg,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final content = Padding(padding: padding, child: child);
    final card = Material(
      color: color ?? (raised ? PFColors.surfaceRaised : PFColors.surface),
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: const BorderSide(color: PFColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, child: content),
    );
    if (margin == null) return card;
    return Padding(padding: margin!, child: card);
  }
}
