import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';

class PFSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const PFSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = PFRadius.sm,
  });

  @override
  State<PFSkeleton> createState() => _PFSkeletonState();
}

class _PFSkeletonState extends State<PFSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 1, 0),
              end: Alignment(t + 1, 0),
              colors: const [
                PFColors.surfaceRaised,
                PFColors.surfaceHigh,
                PFColors.surfaceRaised,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// Convenience: a card-shaped skeleton block.
class PFSkeletonCard extends StatelessWidget {
  final double height;
  const PFSkeletonCard({super.key, this.height = 76});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(PFSpacing.lg),
      decoration: BoxDecoration(
        color: PFColors.surface,
        borderRadius: BorderRadius.circular(PFRadius.lg),
        border: Border.all(color: PFColors.hairline),
      ),
      child: Row(
        children: [
          const PFSkeleton(width: 56, height: 56, radius: PFRadius.md),
          const SizedBox(width: PFSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                PFSkeleton(width: 160, height: 14),
                SizedBox(height: 10),
                PFSkeleton(width: 100, height: 11),
              ],
            ),
          ),
          const SizedBox(width: PFSpacing.md),
          const PFSkeleton(width: 40, height: 16),
        ],
      ),
    );
  }
}
