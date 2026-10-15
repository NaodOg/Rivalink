import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';
import 'pf_button.dart';

class PFEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const PFEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(
              color: PFColors.surfaceRaised,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: PFColors.textTertiary, size: 30),
          ),
          const SizedBox(height: PFSpacing.lg),
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          if (message != null) ...[
            const SizedBox(height: PFSpacing.sm),
            Text(message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: PFSpacing.xl),
            PFButton(
              label: actionLabel!,
              onTap: onAction,
              expand: false,
              dense: true,
            ),
          ],
        ],
      ),
    );
  }
}
