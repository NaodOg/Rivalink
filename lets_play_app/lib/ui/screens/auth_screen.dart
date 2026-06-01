import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/playfair_theme.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';

class AuthScreen extends StatefulWidget {
  final SessionController session;
  const AuthScreen({super.key, required this.session});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController(text: 'henok@example.com');
  final _password = TextEditingController(text: 'password123');
  final _name = TextEditingController(text: 'Henok T');
  final _phone = TextEditingController(text: '+251911000000');
  final _location = TextEditingController(text: 'Addis Ababa, Ethiopia');
  bool _signup = false;
  bool _hidePassword = true;

  Future<void> _submit() async {
    bool ok;
    if (_signup) {
      ok = await widget.session.signup(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        location: _location.text.trim(),
      );
    } else {
      ok = await widget.session.login(_email.text.trim(), _password.text);
    }
    if (!mounted) return;
    if (ok) {
      Navigator.pushReplacementNamed(context, AppRoutes.shell);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Authentication failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PFColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            const SizedBox(height: 10),
            Container(
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: PFColors.border),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF202820), Color(0xFF121712)],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -40,
                    top: -50,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0x1AC7E96A),
                      ),
                    ),
                  ),
                  Positioned(
                    left: -26,
                    bottom: -35,
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0x1432FF6A),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.sports_soccer_rounded, color: PFColors.accent, size: 30),
                            SizedBox(width: 10),
                            Text('PlayFair', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                          ],
                        ),
                        Spacer(),
                        Text('Your game starts here.', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.05)),
                        SizedBox(height: 8),
                        Text('Book fields, join matches, and build your sports circle in Addis.', style: TextStyle(color: PFColors.muted, height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: PFColors.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: PFColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _signup = false),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: !_signup ? PFColors.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        alignment: Alignment.center,
                        child: Text('LOGIN', style: TextStyle(color: !_signup ? PFColors.background : PFColors.text, fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _signup = true),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: _signup ? PFColors.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        alignment: Alignment.center,
                        child: Text('SIGN UP', style: TextStyle(color: _signup ? PFColors.background : PFColors.text, fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            PFCard(
              child: Column(
                children: [
                  if (_signup) ...[
                    TextField(controller: _name, decoration: const InputDecoration(hintText: 'Full Name')),
                    const SizedBox(height: 12),
                    TextField(controller: _phone, decoration: const InputDecoration(hintText: 'Phone Number')),
                    const SizedBox(height: 12),
                    TextField(controller: _location, decoration: const InputDecoration(hintText: 'Location (e.g. Addis Ababa)')),
                    const SizedBox(height: 12),
                  ],
                  TextField(controller: _email, decoration: const InputDecoration(hintText: 'Email')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _hidePassword,
                    decoration: InputDecoration(
                      hintText: 'Password',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _hidePassword = !_hidePassword),
                        icon: Icon(_hidePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: PFColors.muted),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  PFButton(label: _signup ? 'Create Account' : 'Continue', onTap: _submit),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text('By continuing, you agree to PlayFair Terms & Privacy.', style: TextStyle(color: PFColors.muted, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
