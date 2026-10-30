import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/rivalink_theme.dart';

/// Floating bottom dock with a notched cradle for the host action.
class BottomTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final VoidCallback onHost;

  const BottomTabBar({
    super.key,
    required this.index,
    required this.onChanged,
    required this.onHost,
  });

  static const double _dockHeight = 64;
  static const double _dockBottom = 8;
  static const double _centreGap = 70;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, _dockBottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 86,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _dockHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 28,
                        spreadRadius: -6,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: CustomPaint(painter: const _DockPainter()),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _dockHeight,
                child: Row(
                  children: [
                    _item(context, 0, Icons.home_rounded, L10n.t('nav.home')),
                    _item(context, 1, Icons.explore_rounded, L10n.t('nav.explore')),
                    const SizedBox(width: _centreGap),
                    _item(context, 2, Icons.emoji_events_rounded, L10n.t('nav.leagues')),
                    _item(context, 3, Icons.person_rounded, L10n.t('nav.profile')),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(child: _host(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, int i, IconData icon, String label) {
    final active = i == index;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged(i);
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                duration: PFMotion.fast,
                curve: PFMotion.emphasized,
                scale: active ? 1.06 : 1,
                child: AnimatedContainer(
                  duration: PFMotion.fast,
                  curve: PFMotion.emphasized,
                  width: 40,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: active
                          ? [
                              PFColors.primary.withValues(alpha: 0.24),
                              PFColors.primary.withValues(alpha: 0.06),
                            ]
                          : [Colors.transparent, Colors.transparent],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: active
                          ? PFColors.primary.withValues(alpha: 0.30)
                          : Colors.transparent,
                    ),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: PFColors.primary.withValues(alpha: 0.22),
                              blurRadius: 12,
                              spreadRadius: -3,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    icon,
                    color: active ? PFColors.primary : PFColors.textTertiary,
                    size: 21,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: active ? PFColors.text : PFColors.textTertiary,
                  fontSize: 10.2,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: PFMotion.fast,
                curve: PFMotion.emphasized,
                width: active ? 12 : 0,
                height: 2,
                decoration: BoxDecoration(
                  color: active ? PFColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(PFRadius.pill),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: PFColors.primary.withValues(alpha: 0.55),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _host(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Host a match',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.mediumImpact();
          onHost();
        },
        child: SizedBox(
          width: 60,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: PFColors.primary.withValues(alpha: 0.20),
                        ),
                      ),
                    ),
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          center: Alignment(-0.45, -0.55),
                          radius: 1.1,
                          colors: [
                            Color(0xFF7B9AFF),
                            PFColors.primary,
                            Color(0xFF1233B8),
                          ],
                          stops: [0, 0.42, 1],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: PFColors.primary.withValues(alpha: 0.42),
                            blurRadius: 20,
                            spreadRadius: -2,
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: PFColors.onPrimary,
                        size: 27,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                L10n.t('nav.host'),
                style: const TextStyle(
                  color: PFColors.textSecondary,
                  fontSize: 10.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Path _dockPath(Size size) {
  final dock = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(26),
      ),
    );
  final notch = Path()
    ..addOval(
      Rect.fromCircle(
        center: Offset(size.width / 2, -12),
        radius: 44,
      ),
    );
  return Path.combine(PathOperation.difference, dock, notch);
}

class _DockPainter extends CustomPainter {
  const _DockPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = _dockPath(size);

    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF17171B), Color(0xFF0D0D10)],
        ).createShader(rect),
    );

    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 0.2),
          radius: 0.9,
          colors: [
            PFColors.primary.withValues(alpha: 0.09),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A3A42), Color(0xFF202025), Color(0xFF17171B)],
          stops: [0, 0.45, 1],
        ).createShader(rect),
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.13),
            Colors.transparent,
          ],
          stops: const [0, 0.32],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _DockPainter oldDelegate) => false;
}
