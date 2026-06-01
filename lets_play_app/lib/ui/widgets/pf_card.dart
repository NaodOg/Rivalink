import 'package:flutter/material.dart';

import '../../core/theme/playfair_theme.dart';

class PFCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const PFCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: PFColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PFColors.border),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(borderRadius: BorderRadius.circular(18), onTap: onTap, child: card);
  }
}
