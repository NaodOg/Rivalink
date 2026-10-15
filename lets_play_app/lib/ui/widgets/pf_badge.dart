import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';

class PFBadge extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;
  final bool solid;

  const PFBadge({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? PFColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? c : c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(PFRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: solid ? PFColors.onPrimary : c),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: solid ? PFColors.onPrimary : c,
            ),
          ),
        ],
      ),
    );
  }
}
