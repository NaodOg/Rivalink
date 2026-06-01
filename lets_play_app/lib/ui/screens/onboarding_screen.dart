import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/theme/playfair_theme.dart';
import '../widgets/pf_button.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  Future<void> _finish(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!context.mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.auth);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PFColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Text('Welcome to\nPlayFair', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, height: 1.05)),
              const SizedBox(height: 16),
              const Text('Book fields, host matches, create teams, and run leagues in Addis Ababa.', style: TextStyle(color: PFColors.muted, fontSize: 15, height: 1.5)),
              const Spacer(),
              PFButton(label: 'Get Started', onTap: () => _finish(context)),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }
}
