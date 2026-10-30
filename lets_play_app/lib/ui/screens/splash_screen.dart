import 'package:flutter/material.dart';

import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/victiqo_wordmark.dart';

/// Branded first frame: the pin with the VICTIQO wordmark directly underneath.
/// Android 12+ cannot place content under the system splash icon, so the
/// system splash shows only the matching background and this screen provides
/// the lockup, handing off to [nextRoute] once it has been on screen briefly.
class SplashScreen extends StatefulWidget {
  final SessionController session;
  final String nextRoute;
  const SplashScreen({super.key, required this.session, required this.nextRoute});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.04),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(widget.nextRoute, (r) => false);
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
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/rivalink_pin.png',
                  height: 150,
                  filterQuality: FilterQuality.high,
                ),
                const SizedBox(height: 12),
                const VictiqoWordmark(
                  fontSize: 44,
                  letterSpacing: 6,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
