import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_badge.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_sport_tile.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _pages = [
    _Slide(
      sport: 'soccer',
      eyebrow: 'DISCOVER',
      title: 'Find a game\nnear you.',
      body: 'Browse matches and book pitches across Addis — by sport, area and time.',
      chips: ['5v5', 'Bole', 'Tonight'],
    ),
    _Slide(
      sport: 'basketball',
      eyebrow: 'COMPETE',
      title: 'Play ranked.\nClimb the table.',
      body: 'Earn an Elo per sport, join leagues and prove you are the best squad.',
      chips: ['Elo', 'Leagues', 'MVP'],
    ),
    _Slide(
      sport: 'volleyball',
      eyebrow: 'CONNECT',
      title: 'Build your\nsports circle.',
      body: 'Teams, chat, invites and venues — everything your crew needs in one place.',
      chips: ['Teams', 'Chat', 'Venues'],
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.auth, (r) => false);
  }

  void _next() {
    if (_index < _pages.length - 1) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    return Scaffold(
      backgroundColor: PFColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  Text('Rivalink',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge!
                          .copyWith(letterSpacing: 3)),
                  const Spacer(),
                  TextButton(onPressed: _finish, child: const Text('Skip')),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _PageView(slide: _pages[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  for (int i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: PFMotion.fast,
                      margin: const EdgeInsets.only(right: 6),
                      width: i == _index ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _index ? PFColors.primary : PFColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(PFRadius.pill),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: PFButton(
                label: last ? 'Get started' : 'Continue',
                icon: last ? null : Icons.arrow_forward_rounded,
                onTap: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final String sport;
  final String eyebrow;
  final String title;
  final String body;
  final List<String> chips;
  const _Slide({
    required this.sport,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.chips,
  });
}

class _PageView extends StatelessWidget {
  final _Slide slide;
  const _PageView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PFRadius.xxl),
                border: Border.all(color: PFColors.border),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [PFColors.surfaceRaised, PFColors.surface],
                ),
              ),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: PFSportTile(sport: slide.sport, size: 132),
                  ),
                  Positioned(
                    left: 20,
                    top: 20,
                    child: PFBadge(
                        label: slide.eyebrow,
                        color: PFSport.color(slide.sport),
                        solid: true),
                  ),
                  Positioned(
                    right: 18,
                    top: 18,
                    child: _MiniStat(
                      label: 'LIVE',
                      value: '2 – 1',
                      color: PFSport.color(slide.sport),
                    ),
                  ),
                  Positioned(
                    right: 18,
                    top: 92,
                    child: _MiniStat(
                      label: 'ELO',
                      value: '1,240',
                      color: PFColors.secondary,
                    ),
                  ),
                  Positioned(
                    left: 20,
                    bottom: 20,
                    child: Row(
                      children: slide.chips
                          .map((c) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: PFBadge(
                                    label: c, color: PFSport.color(slide.sport)),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(slide.title, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 12),
          Text(slide.body, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: PFColors.surface,
        borderRadius: BorderRadius.circular(PFRadius.md),
        border: Border.all(color: PFColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1, color: color)),
          const SizedBox(height: 3),
          Text(value, style: PFType.number.copyWith(fontSize: 16)),
        ],
      ),
    );
  }
}
