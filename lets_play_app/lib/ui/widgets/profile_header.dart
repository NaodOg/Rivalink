import 'package:flutter/material.dart';

import '../../core/theme/playfair_theme.dart';
import 'pf_card.dart';

class ProfileHeader extends StatelessWidget {
  final String name;
  final String location;
  final String? profileImage;
  final Map<String, String> metrics;

  const ProfileHeader({
    super.key,
    required this.name,
    required this.location,
    this.profileImage,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    return PFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: PFColors.cardSoft,
                backgroundImage: profileImage != null && profileImage!.isNotEmpty
                    ? NetworkImage(profileImage!)
                    : null,
                child: (profileImage == null || profileImage!.isEmpty)
                    ? const Icon(Icons.person, color: PFColors.accent)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(location, style: const TextStyle(color: PFColors.muted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: metrics.entries.map((e) {
              return Expanded(
                child: Column(
                  children: [
                    Text(e.value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 3),
                    Text(e.key, style: const TextStyle(color: PFColors.muted, fontSize: 11)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
