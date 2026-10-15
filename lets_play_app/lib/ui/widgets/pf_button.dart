import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';

enum PFButtonVariant { primary, secondary, ghost }

class PFButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final PFButtonVariant variant;
  final bool expand;
  final bool loading;
  final bool dense;
  final IconData? icon;

  const PFButton({
    super.key,
    required this.label,
    required this.onTap,
    this.variant = PFButtonVariant.primary,
    this.expand = true,
    this.loading = false,
    this.dense = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final spinnerColor = variant == PFButtonVariant.primary
        ? PFColors.onPrimary
        : PFColors.textSecondary;

    final child = loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: spinnerColor),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: PFSpacing.sm),
              ],
              Text(label),
            ],
          );

    final onPressed = loading ? null : onTap;

    final Widget button = switch (variant) {
      PFButtonVariant.secondary => OutlinedButton(onPressed: onPressed, child: child),
      PFButtonVariant.ghost => TextButton(onPressed: onPressed, child: child),
      PFButtonVariant.primary => FilledButton(onPressed: onPressed, child: child),
    };

    return SizedBox(
      width: expand ? double.infinity : null,
      height: dense ? 46 : 52,
      child: button,
    );
  }
}
