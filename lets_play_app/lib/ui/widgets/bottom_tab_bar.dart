import 'package:flutter/material.dart';

import '../../core/theme/playfair_theme.dart';

class BottomTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const BottomTabBar({super.key, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const tabs = [
      (Icons.home_rounded, 'Home'),
      (Icons.sports_soccer_rounded, 'Matches'),
      (Icons.stadium_rounded, 'Fields'),
      (Icons.emoji_events_rounded, 'Leagues'),
      (Icons.leaderboard_rounded, 'Rankings'),
      (Icons.person_rounded, 'Profile'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0D0A),
        border: Border(top: BorderSide(color: PFColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(tabs.length, (i) {
              final active = i == index;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(tabs[i].$1, color: active ? PFColors.accent : PFColors.muted, size: 22),
                      const SizedBox(height: 4),
                      Text(
                        tabs[i].$2,
                        style: TextStyle(color: active ? PFColors.accent : PFColors.muted, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
