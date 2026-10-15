import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';

/// Pill segmented control used across the app (Explore, Auth, Ranking, Host).
/// The selected segment fills its entire half, edge to edge.
class PFSegmented extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  /// Filled = accent fill on the active segment (primary choices);
  /// otherwise a raised neutral fill (view toggles).
  final bool accent;

  const PFSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(PFRadius.pill);
    return SizedBox(
      height: 48,
      child: Container(
        decoration: BoxDecoration(
          color: PFColors.surface,
          borderRadius: radius,
          border: Border.all(color: PFColors.border),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(labels.length, (i) {
            final active = i == index;
            final Color bg = active
                ? (accent ? PFColors.primary : PFColors.surfaceHigh)
                : Colors.transparent;
            final Color fg = active
                ? (accent ? PFColors.onPrimary : PFColors.text)
                : PFColors.textTertiary;
            return Expanded(
              child: Semantics(
                button: true,
                selected: active,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: PFMotion.fast,
                    curve: PFMotion.emphasized,
                    color: bg,
                    alignment: Alignment.center,
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    ),
  );
  }
}
