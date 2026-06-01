import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/playfair_theme.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_scaffold.dart';

class SettingsScreen extends StatelessWidget {
  final SessionController session;
  const SettingsScreen({super.key, required this.session});

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PFColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Leave PlayFair?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to log out?', style: TextStyle(color: PFColors.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log Out', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await session.logout();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.auth, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user = session.user ?? <String, dynamic>{};
    final name = user['name']?.toString() ?? 'Player';
    final email = user['email']?.toString() ?? 'player@playfair.app';
    final profileImage = user['profile_image']?.toString();

    return PFScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          PFCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: PFColors.cardSoft,
                  backgroundImage: profileImage != null && profileImage.isNotEmpty
                      ? NetworkImage(profileImage)
                      : null,
                  child: (profileImage == null || profileImage.isEmpty)
                      ? Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: PFColors.accent))
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(email, style: const TextStyle(fontSize: 13, color: PFColors.muted)),
                      if (user['location']?.toString() != null && user['location'].toString().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.location_on_rounded, size: 12, color: PFColors.muted),
                            const SizedBox(width: 4),
                            Text(user['location'].toString(), style: const TextStyle(fontSize: 12, color: PFColors.muted)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(title: 'ACCOUNT', children: [
            _Tile(icon: Icons.person_outline_rounded, label: 'Edit Profile', onTap: () => Navigator.pushNamed(context, AppRoutes.editProfile)),
            _divider,
            _Tile(icon: Icons.lock_outline_rounded, label: 'Change Password', onTap: () {}),
          ]),
          const SizedBox(height: 14),
          _Section(title: 'PREFERENCES', children: [
            _Tile(icon: Icons.language_rounded, label: 'Language', trailing: const Text('English', style: TextStyle(color: PFColors.muted, fontSize: 14)), onTap: () {}),
            _divider,
            _Tile(icon: Icons.attach_money_rounded, label: 'Currency', trailing: const Text('ETB Br', style: TextStyle(color: PFColors.muted, fontSize: 14)), onTap: () {}),
            _divider,
            _Tile(icon: Icons.color_lens_outlined, label: 'Theme', trailing: const Text('Dark', style: TextStyle(color: PFColors.muted, fontSize: 14)), onTap: () {}),
          ]),
          const SizedBox(height: 14),
          _Section(title: 'NOTIFICATIONS', children: [
            _ToggleTile(icon: Icons.notifications_outlined, label: 'Push Notifications', value: true),
            _divider,
            _ToggleTile(icon: Icons.event_available_rounded, label: 'Match Reminders', value: true),
            _divider,
            _ToggleTile(icon: Icons.emoji_events_outlined, label: 'League Updates', value: false),
          ]),
          const SizedBox(height: 14),
          _Section(title: 'ABOUT', children: [
            _Tile(icon: Icons.info_outline_rounded, label: 'App Version', trailing: const Text('1.0.0', style: TextStyle(color: PFColors.muted, fontSize: 14)), onTap: () {}),
            _divider,
            _Tile(icon: Icons.shield_outlined, label: 'Privacy Policy', onTap: () {}),
            _divider,
            _Tile(icon: Icons.description_outlined, label: 'Terms of Service', onTap: () {}),
          ]),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: PFButton(
              label: 'Log Out',
              onTap: () => _logout(context),
            ),
          ),
          const SizedBox(height: 12),
          const Center(child: Text('PlayFair v1.0.0', style: TextStyle(fontSize: 11, color: PFColors.muted))),
        ],
      ),
    );
  }
}

Widget get _divider => Divider(height: 1, color: PFColors.border.withValues(alpha: 0.25), indent: 48);

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, bottom: 8),
          child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: PFColors.muted, letterSpacing: 1)),
        ),
        PFCard(
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.label, this.trailing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: PFColors.muted, size: 22),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: PFColors.muted, size: 20),
      onTap: onTap,
    );
  }
}

class _ToggleTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool value;
  const _ToggleTile({required this.icon, required this.label, required this.value});

  @override
  State<_ToggleTile> createState() => _ToggleTileState();
}

class _ToggleTileState extends State<_ToggleTile> {
  late bool _value;
  @override
  void initState() { super.initState(); _value = widget.value; }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(widget.icon, color: PFColors.muted, size: 22),
      title: Text(widget.label, style: const TextStyle(fontSize: 15)),
      trailing: Switch(
        value: _value,
        activeColor: PFColors.accent,
        onChanged: (v) => setState(() => _value = v),
      ),
      onTap: () => setState(() => _value = !_value),
    );
  }
}
