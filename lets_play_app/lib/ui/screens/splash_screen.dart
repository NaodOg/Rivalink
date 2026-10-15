import 'package:flutter/material.dart';

import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_logo.dart';
import '../../main.dart';

class SplashScreen extends StatefulWidget {
  final SessionController session;
  const SplashScreen({super.key, required this.session});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.5, curve: Curves.easeOut));
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.35),
    end: Offset.zero,
  ).animate(CurvedAnimation(
      parent: _c, curve: const Interval(0.1, 0.7, curve: Curves.easeOutCubic)));

  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    await Future.delayed(const Duration(milliseconds: 900));
    final route = await resolveInitialRoute(widget.session);
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(route, (r) => false);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PFColors.background,
      body: Stack(
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: PFColors.primary.withValues(alpha: 0.06),
              ),
            ),
          ),
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PFLogo(
                      markSize: 104,
                      wordSize: 40,
                      vertical: true,
                      wordColor: Color(0xFF3BAEE0),
                    ),
                    const SizedBox(height: 16),
                    Text('FIND YOUR RIVALS. MAKE YOUR MARK.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                              letterSpacing: 2.4,
                              color: PFColors.textSecondary,
                            )),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: AnimatedBuilder(
                    animation: _fade,
                    builder: (context, _) => LinearProgressIndicator(
                      value: _fade.value,
                      minHeight: 3,
                      backgroundColor: PFColors.surfaceRaised,
                      valueColor:
                          const AlwaysStoppedAnimation(PFColors.primary),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
