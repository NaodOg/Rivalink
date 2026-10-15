import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/rivalink_theme.dart';

/// Bottom navigation: four destinations with a raised center "Host" action.
/// Page indices: 0 Home · 1 Explore · 2 Leagues · 3 Profile.
class BottomTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final VoidCallback onHost;

  const BottomTabBar({
    super.key,
    required this.index,
    required this.onChanged,
    required this.onHost,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PFColors.background,
        border: Border(top: BorderSide(color: PFColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              _item(context, 0, Icons.home_rounded, L10n.t('nav.home')),
              _item(context, 1, Icons.explore_rounded, L10n.t('nav.explore')),
              _host(context),
              _item(context, 2, Icons.emoji_events_rounded, L10n.t('nav.leagues')),
              _item(context, 3, Icons.person_rounded, L10n.t('nav.profile')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, int i, IconData icon, String label) {
    final active = i == index;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: InkWell(
          onTap: () => onChanged(i),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: PFMotion.fast,
                curve: PFMotion.emphasized,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: active
                      ? PFColors.primary.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(PFRadius.pill),
                ),
                child: Icon(icon,
                    color: active ? PFColors.primary : PFColors.textTertiary,
                    size: 22),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: active ? PFColors.text : PFColors.textTertiary,
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _host(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        label: 'Host a match',
        child: InkWell(
          onTap: onHost,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: PFColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: PFColors.primary.withValues(alpha: 0.25),
                      blurRadius: 14,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: const Icon(Icons.add_rounded,
                    color: PFColors.onPrimary, size: 26),
              ),
              const SizedBox(height: 1),
              Text(L10n.t('nav.host'),
                  style: const TextStyle(
                      color: PFColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
