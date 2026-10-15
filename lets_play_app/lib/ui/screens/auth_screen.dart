import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_badge.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_logo.dart';
import '../widgets/pf_segmented.dart';

class AuthScreen extends StatefulWidget {
  final SessionController session;
  const AuthScreen({super.key, required this.session});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  bool _signup = false;
  bool _hidePassword = true;
  bool _busy = false;

  late final AnimationController _entrance = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _kenBurns = AnimationController(
      vsync: this, duration: const Duration(seconds: 18))..repeat(reverse: true);
  late final AnimationController _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400));

  late final Animation<double> _heroFade =
      CurvedAnimation(parent: _entrance, curve: const Interval(0.0, 0.5, curve: Curves.easeOut));
  late final Animation<Offset> _sheetSlide = Tween<Offset>(
    begin: const Offset(0, 0.14),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _entrance, curve: const Interval(0.15, 1.0, curve: Curves.easeOutCubic)));

  Timer? _tagTimer;
  int _tagIndex = 0;
  static const _taglines = [
    'Find your game.',
    'Fill your squad.',
    'Climb the table.',
    'Own the pitch.',
    'Play in Addis.',
  ];

  @override
  void initState() {
    super.initState();
    _entrance.forward();
    _tagTimer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (mounted) setState(() => _tagIndex = (_tagIndex + 1) % _taglines.length);
    });
  }

  @override
  void dispose() {
    _tagTimer?.cancel();
    _entrance.dispose();
    _kenBurns.dispose();
    _shake.dispose();
    for (final c in [_email, _password, _name, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final bool ok;
    if (_signup) {
      ok = await widget.session.signup(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        location: '',
      );
    } else {
      ok = await widget.session.login(_email.text.trim(), _password.text);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Navigator.pushReplacementNamed(context, AppRoutes.shell);
    } else {
      _shake.forward(from: 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.session.errorMessage ?? 'Authentication failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom > 0;
    final heroH = keyboard ? 160.0 : media.size.height * 0.42;

    return Scaffold(
      backgroundColor: PFColors.background,
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            height: heroH,
            child: FadeTransition(opacity: _heroFade, child: _hero(context)),
          ),
          Expanded(
            child: SlideTransition(
              position: _sheetSlide,
              child: AnimatedBuilder(
                animation: _shake,
                builder: (context, child) {
                  final dx = math.sin(_shake.value * math.pi * 5) * (1 - _shake.value) * 12;
                  return Transform.translate(offset: Offset(dx, 0), child: child);
                },
                child: _sheet(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero (photo + Ken Burns + pitch lines + rotating tagline) ──
  Widget _hero(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: AnimatedBuilder(
            animation: _kenBurns,
            builder: (context, _) {
              final t = _kenBurns.value;
              return Transform.scale(
                scale: 1.06 + 0.08 * t,
                child: Transform.translate(
                  offset: Offset(-12 + 24 * t, 0),
                  child: Image.asset(
                    'assets/images/hero_soccer.jpg',
                    fit: BoxFit.cover,
                    alignment: const Alignment(0.2, 0.35),
                  ),
                ),
              );
            },
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xCC0A0B0A), Color(0x330A0B0A), Color(0xFF0A0B0A)],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),
        const CustomPaint(painter: _PitchPainter()),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 54, 20, 16),
          child: LayoutBuilder(
            builder: (context, c) {
              final compact = c.maxHeight < 230;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PFLogo(markSize: 34, wordSize: 20),
                  const Spacer(),
                  if (!compact) ...[
                    Text('ADDIS ABABA',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall!
                            .copyWith(letterSpacing: 4, color: PFColors.textSecondary)),
                    const SizedBox(height: 8),
                  ],
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Text(
                      _taglines[_tagIndex],
                      key: ValueKey(_tagIndex),
                      style: Theme.of(context)
                          .textTheme
                          .displaySmall!
                          .copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        PFBadge(label: '5v5 · Bole', color: PFColors.textSecondary),
                        SizedBox(width: 8),
                        PFBadge(label: 'Live now', color: PFColors.primary),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Form sheet ──
  Widget _sheet(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: PFColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(PFRadius.xxl)),
        border: const Border(top: BorderSide(color: PFColors.hairline)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: PFColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(_signup ? 'Create your account' : 'Welcome back',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            _signup
                ? 'Join the Addis sports community.'
                : 'Log in to keep booking, hosting and competing.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          PFSegmented(
            labels: const ['Log in', 'Sign up'],
            index: _signup ? 1 : 0,
            accent: true,
            onChanged: (i) => setState(() => _signup = i == 1),
          ),
          const SizedBox(height: 18),
          if (_signup) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: 'Full name'),
                  ),
                ),
                const SizedBox(width: PFSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: '+251…'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: PFSpacing.md),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'Email',
              prefixIcon: Icon(Icons.alternate_email_rounded, color: PFColors.textTertiary),
            ),
          ),
          const SizedBox(height: PFSpacing.md),
          TextField(
            controller: _password,
            obscureText: _hidePassword,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded, color: PFColors.textTertiary),
              suffixIcon: IconButton(
                icon: Icon(
                  _hidePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: PFColors.textTertiary,
                ),
                onPressed: () => setState(() => _hidePassword = !_hidePassword),
              ),
            ),
          ),
          const SizedBox(height: PFSpacing.xl),
          PFButton(
            label: _signup ? 'Create account' : 'Continue',
            icon: Icons.arrow_forward_rounded,
            loading: _busy,
            onTap: _submit,
          ),
          const SizedBox(height: PFSpacing.lg),
          Center(
            child: Text(
              'By continuing you agree to Rivalink Terms & Privacy.',
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Faint pitch markings over the hero photo.
class _PitchPainter extends CustomPainter {
  const _PitchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.white.withValues(alpha: 0.07);
    final cx = size.width * 0.5;
    final cy = size.height * 0.62;
    canvas.drawCircle(Offset(cx, cy), size.width * 0.30, paint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), paint);
    canvas.drawCircle(Offset(cx, cy), 3.5, Paint()..color = Colors.white.withValues(alpha: 0.10));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
