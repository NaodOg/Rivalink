import 'package:flutter/material.dart';

import '../../core/state/session_controller.dart';
import '../../core/theme/playfair_theme.dart';
import '../../main.dart';

class SplashScreen extends StatefulWidget {
  final SessionController session;
  const SplashScreen({super.key, required this.session});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    await Future.delayed(const Duration(milliseconds: 900));
    final route = await resolveInitialRoute(widget.session);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: PFColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_soccer_rounded, size: 48, color: PFColors.accent),
            SizedBox(height: 12),
            Text('PlayFair', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            SizedBox(height: 8),
            Text('Play. Connect. Compete.', style: TextStyle(color: PFColors.muted)),
          ],
        ),
      ),
    );
  }
}
