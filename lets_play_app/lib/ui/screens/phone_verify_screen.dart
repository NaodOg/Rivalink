import 'package:flutter/material.dart';

import '../../core/data/services/phone_verify_service.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_badge.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';

class PhoneVerifyScreen extends StatefulWidget {
  final SessionController session;
  const PhoneVerifyScreen({super.key, required this.session});

  @override
  State<PhoneVerifyScreen> createState() => _PhoneVerifyScreenState();
}

class _PhoneVerifyScreenState extends State<PhoneVerifyScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _loading = true;
  bool _verified = false;
  bool _busy = false;
  String? _devCode;
  String _currentPhone = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    final res = await PhoneVerifyService.status(token);
    if (!mounted) return;
    setState(() {
      _currentPhone = res['phone']?.toString() ?? '';
      _phone.text = _currentPhone;
      _verified = res['phone_verified'] == true;
      _loading = false;
    });
  }

  Future<void> _send() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() => _busy = true);
    final res = await PhoneVerifyService.sendCode(token,
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _devCode = res['dev_code']?.toString();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res['error']?.toString() ??
          (res['sent'] == true ? 'Code sent by SMS' : 'Code generated (dev mode)')),
    ));
  }

  Future<void> _verify() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() => _busy = true);
    final res = await PhoneVerifyService.verify(token, _code.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['success'] == true) {
      setState(() => _verified = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Phone verified')));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(res['error']?.toString() ?? 'Failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PFColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Verify phone'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PFColors.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                PFCard(
                  raised: true,
                  child: Row(
                    children: [
                      const Icon(Icons.phone_iphone_rounded, color: PFColors.primary),
                      const SizedBox(width: PFSpacing.md),
                      Expanded(
                        child: Text(
                          _currentPhone.isEmpty ? 'No phone on file' : _currentPhone,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      PFBadge(
                        label: _verified ? 'VERIFIED' : 'UNVERIFIED',
                        color: _verified ? PFColors.primary : PFColors.warning,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PFSpacing.xl),
                Text('PHONE NUMBER', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: PFSpacing.sm),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  enabled: !_verified,
                  decoration: const InputDecoration(hintText: '+2519…'),
                ),
                const SizedBox(height: PFSpacing.md),
                PFButton(
                  label: 'Send code',
                  variant: PFButtonVariant.secondary,
                  loading: _busy,
                  onTap: _verified ? null : _send,
                ),
                if (_devCode != null) ...[
                  const SizedBox(height: PFSpacing.md),
                  PFCard(
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            color: PFColors.warning, size: 18),
                        const SizedBox(width: PFSpacing.sm),
                        Text('Dev code: $_devCode',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: PFSpacing.lg),
                Text('ENTER CODE', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: PFSpacing.sm),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  enabled: !_verified,
                  style: PFType.number.copyWith(fontSize: 20, letterSpacing: 6),
                  decoration: const InputDecoration(hintText: '••••••', counterText: ''),
                ),
                const SizedBox(height: PFSpacing.lg),
                PFButton(
                  label: _verified ? 'Verified' : 'Verify',
                  loading: _busy,
                  onTap: _verified ? null : _verify,
                ),
              ],
            ),
    );
  }
}
