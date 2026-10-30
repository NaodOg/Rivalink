import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/data/media_config.dart';
import '../../core/l10n/l10n.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../../core/data/services/analytics_service.dart';
import '../widgets/pf_badge.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_scaffold.dart';
import '../widgets/victiqo_wordmark.dart';

class SettingsScreen extends StatelessWidget {
  final SessionController session;
  const SettingsScreen({super.key, required this.session});

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PFColors.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Leave Victiqo?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to log out?',
            style: TextStyle(color: PFColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Log Out',
                  style: TextStyle(color: PFColors.danger))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await session.logout();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.auth, (_) => false);
  }

  Future<void> _pickLanguage(BuildContext context) async {
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: PFColors.surfaceRaised,
        title: const Text('Language'),
        children: L10n.languageNames.entries
            .map((e) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, e.key),
                  child: Text(e.value, style: const TextStyle(fontSize: 15)),
                ))
            .toList(),
      ),
    );
    if (code != null) await L10n.setLanguage(code);
  }

  @override
  Widget build(BuildContext context) {
    final user = session.user ?? <String, dynamic>{};
    final name = user['name']?.toString() ?? 'Player';
    final email = user['email']?.toString() ?? 'player@Victiqo.app';
    final location = user['location']?.toString() ?? '';
    final isPremium = user['is_premium'] == true;
    final profileImage = MediaConfig.resolve(user['profile_image']?.toString());
    final favs = (user['favorite_sports'] as List?)?.cast<String>() ?? const [];
    final sport = favs.isNotEmpty ? favs.first : '';

    return PFScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _ProfileHero(
            name: name,
            email: email,
            location: location,
            isPremium: isPremium,
            profileImage: profileImage,
            sport: sport,
            onTap: () => Navigator.pushNamed(context, AppRoutes.editProfile),
          ),
          const SizedBox(height: 24),
          _Section(
            title: 'Account',
            accent: PFColors.primary,
            children: [
              _Tile(
                icon: Icons.person_outline_rounded,
                label: 'Edit profile',
                tint: PFColors.primary,
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.editProfile),
              ),
              _divider,
              _Tile(
                icon: Icons.phone_iphone_rounded,
                label: 'Verify phone',
                tint: PFColors.primary,
                onTap: () => Navigator.pushNamed(context, AppRoutes.phoneVerify),
              ),
              _divider,
              _Tile(
                icon: Icons.lock_outline_rounded,
                label: 'Change password',
                tint: PFColors.primary,
                onTap: () {},
              ),
            ],
          ),
          _Section(
            title: 'Preferences',
            accent: const Color(0xFFB07CFF),
            children: [
              _Tile(
                icon: Icons.language_rounded,
                label: L10n.t('common.language'),
                tint: const Color(0xFFB07CFF),
                value: L10n.languageNames[L10n.locale.value] ?? 'English',
                showChevron: false,
                onTap: () => _pickLanguage(context),
              ),
              _divider,
              _Tile(
                icon: Icons.attach_money_rounded,
                label: 'Currency',
                tint: const Color(0xFFB07CFF),
                value: 'ETB Br',
                showChevron: false,
                onTap: () {},
              ),
              _divider,
              _Tile(
                icon: Icons.color_lens_outlined,
                label: 'Theme',
                tint: const Color(0xFFB07CFF),
                value: 'Dark',
                showChevron: false,
                onTap: () {},
              ),
            ],
          ),
          _PremiumCard(
            isPremium: isPremium,
            onTap: () => Navigator.pushNamed(context, AppRoutes.subscription),
          ),
          const SizedBox(height: 24),
          _Section(
            title: 'Notifications',
            accent: PFColors.success,
            children: [
              _ToggleTile(
                icon: Icons.notifications_outlined,
                label: 'Push notifications',
                tint: PFColors.success,
                value: true,
              ),
              _divider,
              _ToggleTile(
                icon: Icons.event_available_rounded,
                label: 'Match reminders',
                tint: PFColors.success,
                value: true,
              ),
              _divider,
              _ToggleTile(
                icon: Icons.emoji_events_outlined,
                label: 'League updates',
                tint: PFColors.success,
                value: false,
              ),
            ],
          ),
          _Section(
            title: 'Privacy',
            accent: const Color(0xFFB07CFF),
            children: [
              _AnalyticsToggle(),
            ],
          ),
          _Section(
            title: 'About',
            accent: PFColors.textSecondary,
            children: [
              _Tile(
                icon: Icons.info_outline_rounded,
                label: 'App version',
                tint: PFColors.textSecondary,
                value: '1.0.0',
                showChevron: false,
                onTap: () {},
              ),
              _divider,
              _Tile(
                icon: Icons.shield_outlined,
                label: 'Privacy policy',
                tint: PFColors.textSecondary,
                onTap: () {},
              ),
              _divider,
              _Tile(
                icon: Icons.description_outlined,
                label: 'Terms of service',
                tint: PFColors.textSecondary,
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _logout(context),
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                color: PFColors.danger.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(PFRadius.lg),
                border: Border.all(
                    color: PFColors.danger.withValues(alpha: 0.35)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, size: 18, color: PFColors.danger),
                  SizedBox(width: 8),
                  Text('Log out',
                      style: TextStyle(
                          color: PFColors.danger,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: PFColors.primary, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    const VictiqoWordmark(
                        fontSize: 10, letterSpacing: 2.4),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('v1.0.0 · Made in Addis Ababa',
                    style: TextStyle(
                        fontSize: 11, color: PFColors.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Profile hero ─────────────────────────────────────────────────────────

class _ProfileHero extends StatelessWidget {
  final String name;
  final String email;
  final String location;
  final bool isPremium;
  final String? profileImage;
  final String sport;
  final VoidCallback onTap;

  const _ProfileHero({
    required this.name,
    required this.email,
    required this.location,
    required this.isPremium,
    required this.profileImage,
    required this.sport,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = profileImage != null && profileImage!.isNotEmpty;
    final sportColor = sport.isEmpty ? PFColors.primary : PFSport.color(sport);
    final ringColor = isPremium ? PFColors.gold : PFColors.primary;

    return PFCard(
      padding: EdgeInsets.zero,
      radius: PFRadius.xl,
      raised: true,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(PFRadius.xl)),
                child: Container(
                  height: 76,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        sportColor.withValues(alpha: 0.55),
                        sportColor.withValues(alpha: 0.18),
                        PFColors.surface,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 18, bottom: 12),
                    child: Icon(
                      sport.isEmpty
                          ? Icons.sports_rounded
                          : PFSport.icon(sport),
                      size: 54,
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                bottom: -32,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: PFColors.surface,
                    border: Border.all(color: ringColor, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: PFColors.surfaceHigh,
                    backgroundImage:
                        hasImage ? CachedNetworkImageProvider(profileImage!) : null,
                    child: hasImage
                        ? null
                        : Text(
                            name.isEmpty ? '?' : name[0].toUpperCase(),
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: PFColors.primary),
                          ),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                bottom: -18,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: PFColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(PFRadius.pill),
                    border: Border.all(color: PFColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PFIcons.edit, size: 12, color: PFColors.primary),
                      const SizedBox(width: 5),
                      const Text('Edit',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: PFColors.primary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 40, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                    if (isPremium) ...[
                      const SizedBox(width: 8),
                      PFBadge(
                          label: 'PRO',
                          color: PFColors.gold,
                          icon: PFIcons.crown),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(PFIcons.location,
                          size: 12, color: PFColors.textTertiary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Premium card ─────────────────────────────────────────────────────────

class _PremiumCard extends StatelessWidget {
  final bool isPremium;
  final VoidCallback onTap;
  const _PremiumCard({required this.isPremium, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              PFColors.gold.withValues(alpha: 0.20),
              PFColors.surface,
            ],
            stops: const [0.0, 0.8],
          ),
          borderRadius: BorderRadius.circular(PFRadius.xl),
          border: Border.all(color: PFColors.gold.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: PFColors.gold.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(PFIcons.crown, color: PFColors.gold, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      isPremium ? 'Victiqo Premium' : 'Go Premium',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    isPremium
                        ? 'Your premium is active — enjoy every perk.'
                        : 'Unlimited hosting, teams & league play.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isPremium)
              const PFBadge(label: 'ACTIVE', color: PFColors.gold)
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('100',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: PFColors.gold)),
                  Text('ETB / mo',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: PFColors.gold.withValues(alpha: 0.75))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ── Section + tiles ──────────────────────────────────────────────────────

Widget get _divider => const Divider(
    height: 1, indent: 62, color: PFColors.hairline);

class _Section extends StatelessWidget {
  final String title;
  final Color accent;
  final List<Widget> children;
  const _Section({
    required this.title,
    required this.accent,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(title.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
        PFCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: children),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tint;
  final String? value;
  final bool showChevron;
  final VoidCallback onTap;
  const _Tile({
    required this.icon,
    required this.label,
    required this.tint,
    this.value,
    this.showChevron = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: _IconBubble(icon: icon, tint: tint),
      title: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null) ...[
            Text(value!,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: PFColors.textSecondary)),
            if (showChevron) const SizedBox(width: 4),
          ],
          if (showChevron)
            const Icon(Icons.chevron_right_rounded,
                color: PFColors.textTertiary, size: 20),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _ToggleTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color tint;
  final bool value;
  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.tint,
    required this.value,
  });

  @override
  State<_ToggleTile> createState() => _ToggleTileState();
}

class _ToggleTileState extends State<_ToggleTile> {
  late bool _value;
  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: _IconBubble(icon: widget.icon, tint: widget.tint),
      title: Text(widget.label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      trailing: Switch(
        value: _value,
        activeColor: PFColors.onPrimary,
        activeTrackColor: PFColors.primary,
        inactiveThumbColor: PFColors.textTertiary,
        inactiveTrackColor: PFColors.surfaceHigh,
        onChanged: (v) => setState(() => _value = v),
      ),
      onTap: () => setState(() => _value = !_value),
    );
  }
}

class _IconBubble extends StatelessWidget {
  final IconData icon;
  final Color tint;
  const _IconBubble({required this.icon, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: tint, size: 18),
    );
  }
}

class _AnalyticsToggle extends StatefulWidget {
  @override
  State<_AnalyticsToggle> createState() => _AnalyticsToggleState();
}

class _AnalyticsToggleState extends State<_AnalyticsToggle> {
  late bool _value = AnalyticsService.enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: const _IconBubble(
          icon: Icons.insights_rounded, tint: Color(0xFFB07CFF)),
      title: const Text('Share usage analytics',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: const Text(
        'Help improve Victiqo. No personal data is collected.',
        style: TextStyle(fontSize: 11.5, color: PFColors.textTertiary),
      ),
      trailing: Switch(
        value: _value,
        activeColor: PFColors.onPrimary,
        activeTrackColor: PFColors.primary,
        inactiveThumbColor: PFColors.textTertiary,
        inactiveTrackColor: PFColors.surfaceHigh,
        onChanged: (v) async {
          setState(() => _value = v);
          await AnalyticsService.setEnabled(v);
        },
      ),
      onTap: () async {
        final v = !_value;
        setState(() => _value = v);
        await AnalyticsService.setEnabled(v);
      },
    );
  }
}
