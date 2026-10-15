import 'package:flutter/material.dart';

import '../../core/data/media_config.dart';
import '../../core/theme/rivalink_theme.dart';
import 'pf_badge.dart';
import 'pf_card.dart';

class ProfileHeader extends StatelessWidget {
  final String name;
  final String location;
  final String? profileImage;
  final bool isPremium;
  final bool verified;
  final List<String> favoriteSports;
  final String bio;
  final String? joinedYear;
  final String tierLabel;
  final Color tierColor;
  final VoidCallback? onEditAvatar;

  const ProfileHeader({
    super.key,
    required this.name,
    required this.location,
    this.profileImage,
    this.isPremium = false,
    this.verified = false,
    this.favoriteSports = const [],
    this.bio = '',
    this.joinedYear,
    this.tierLabel = 'Bronze',
    this.tierColor = PFColors.bronze,
    this.onEditAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = MediaConfig.resolve(profileImage) != null;
    return PFCard(
      raised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onEditAvatar,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: PFColors.surface,
                      backgroundImage: hasImage ? NetworkImage(MediaConfig.resolve(profileImage)!) : null,
                      child: hasImage ? null : Icon(PFIcons.user, color: PFColors.textSecondary),
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: PFColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: PFColors.surface, width: 2),
                        ),
                        child: Icon(PFIcons.edit, size: 12, color: PFColors.onPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
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
                          PFBadge(label: 'PRO', color: PFColors.primary, icon: PFIcons.crown),
                        ],
                        if (verified) ...[
                          const SizedBox(width: 6),
                          Icon(PFIcons.verified, color: PFColors.primary, size: 17),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(PFIcons.location, size: 13, color: PFColors.textTertiary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ],
                    ),
                    if (joinedYear != null) ...[
                      const SizedBox(height: 3),
                      Text('Member since $joinedYear',
                          style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: tierColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(PFRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PFIcons.medal, size: 15, color: tierColor),
                const SizedBox(width: 6),
                Text('$tierLabel rank',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: tierColor)),
              ],
            ),
          ),
          if (favoriteSports.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: favoriteSports
                  .map((s) => PFBadge(
                        label: s.isEmpty ? s : s[0].toUpperCase() + s.substring(1),
                        color: PFSport.color(s),
                      ))
                  .toList(),
            ),
          ],
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(bio, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
