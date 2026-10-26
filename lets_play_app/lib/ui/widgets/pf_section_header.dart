import 'package:flutter/material.dart';


/// Section header: small uppercase eyebrow, display title, optional action.
class PFSectionHeader extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;
  final Color? accent;

  const PFSectionHeader({
    super.key,
    this.eyebrow,
    required this.title,
    this.action,
    this.onAction,
    this.trailing,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                Row(
                  children: [
                    if (accent != null) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration:
                            BoxDecoration(color: accent, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(eyebrow!.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
              ],
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
        if (trailing != null) trailing!,
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(action!),
                const Icon(Icons.arrow_forward_rounded, size: 15),
              ],
            ),
          ),
      ],
    );
  }
}
