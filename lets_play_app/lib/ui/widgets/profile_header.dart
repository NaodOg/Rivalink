import 'package:cached_network_image/cached_network_image.dart';
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
  final int followingCount;
  final int followersCount;
  final VoidCallback? onEditAvatar;
  final VoidCallback? onSocialTap;

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
    this.followingCount = 0,
    this.followersCount = 0,
    this.onEditAvatar,
    this.onSocialTap,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedImage = MediaConfig.resolve(profileImage);
    final hasImage = resolvedImage != null;
    final sport = favoriteSports.isNotEmpty ? favoriteSports.first : '';
    final coverColor = sport.isEmpty ? PFColors.primary : PFSport.color(sport);
    final coverIcon = sport.isEmpty ? Icons.sports_rounded : PFSport.icon(sport);
    const avatarRadius = 44.0;

    return PFCard(
      raised: true,
      radius: PFRadius.xl,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover: the avatar overlaps its bottom edge, so the colour band
          // frames the person instead of sitting above them.
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(PFRadius.xl)),
                child: SizedBox(
                  height: 110,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              coverColor.withValues(alpha: 0.62),
                              coverColor.withValues(alpha: 0.20),
                              PFColors.surface,
                            ],
                            stops: const [0.0, 0.55, 1.0],
                          ),
                        ),
                      ),
                      // One large watermark, bleeding off the right edge.
                      Positioned(
                        right: -26,
                        bottom: -30,
                        child: Icon(coverIcon,
                            size: 150,
                            color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      // Inner highlight where the avatar overlaps.
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                bottom: -avatarRadius - 4,
                child: GestureDetector(
                  onTap: onEditAvatar,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: PFColors.surface,
                          border: Border.all(color: tierColor, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                            BoxShadow(
                              color: tierColor.withValues(alpha: 0.22),
                              blurRadius: 18,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: avatarRadius,
                          backgroundColor: PFColors.surfaceHigh,
                          backgroundImage: hasImage
                              ? CachedNetworkImageProvider(resolvedImage)
                              : null,
                          child: hasImage
                              ? null
                              : Icon(PFIcons.user,
                                  color: PFColors.textSecondary, size: 38),
                        ),
                      ),
                      Positioned(
                        bottom: 2,
                        right: -1,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: PFColors.primary,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: PFColors.surface, width: 2),
                          ),
                          child: Icon(PFIcons.edit,
                              size: 11, color: PFColors.onPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            // Top padding clears the half of the avatar that hangs below.
            padding: const EdgeInsets.fromLTRB(20, avatarRadius + 14, 20, 18),
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
                      const SizedBox(width: 6),
                      PFBadge(
                          label: 'PRO',
                          color: PFColors.primary,
                          icon: PFIcons.crown),
                    ],
                    if (verified) ...[
                      const SizedBox(width: 5),
                      Icon(PFIcons.verified, color: PFColors.primary, size: 16),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(PFIcons.location,
                        size: 12, color: PFColors.textTertiary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                    if (joinedYear != null) ...[
                      const SizedBox(width: 8),
                      Text('· since $joinedYear',
                          style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _SocialStat(
                      value: followingCount,
                      label: 'Following',
                      onTap: onSocialTap,
                    ),
                    Container(
                      width: 1,
                      height: 24,
                      margin: const EdgeInsets.symmetric(horizontal: 18),
                      color: PFColors.hairline,
                    ),
                    _SocialStat(
                      value: followersCount,
                      label: 'Followers',
                      onTap: onSocialTap,
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: tierColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(PFRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PFIcons.medal, size: 13, color: tierColor),
                          const SizedBox(width: 5),
                          Text(tierLabel,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: tierColor)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (favoriteSports.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: favoriteSports
                        .map((s) => PFBadge(
                              label: s.isEmpty
                                  ? s
                                  : s[0].toUpperCase() + s.substring(1),
                              color: PFSport.color(s),
                            ))
                        .toList(),
                  ),
                ],
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(bio, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialStat extends StatelessWidget {
  final int value;
  final String label;
  final VoidCallback? onTap;
  const _SocialStat({required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Text('$value',
              style: PFType.number.copyWith(
                  fontSize: 19, fontWeight: FontWeight.w800, color: PFColors.text)),
          const SizedBox(height: 1),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
