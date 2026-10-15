import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';
import '../../core/data/media_config.dart';
import '../../core/data/services/venue_service.dart';
import 'pf_card.dart';

class FieldCard extends StatelessWidget {
  final Venue venue;
  final VoidCallback? onTap;

  const FieldCard({super.key, required this.venue, this.onTap});

  Widget _placeholder() {
    return Container(
      width: 88,
      height: 72,
      decoration: BoxDecoration(
        color: PFColors.surfaceRaised,
        borderRadius: BorderRadius.circular(PFRadius.md),
        border: Border.all(color: PFColors.border),
      ),
      alignment: Alignment.center,
      child: Icon(PFIcons.venue, color: PFColors.primary, size: 26),
    );
  }

  Widget _thumb() {
    final img = MediaConfig.resolve(venue.primaryImage);
    if (img != null && img.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(PFRadius.md),
        child: Image.network(
          img,
          width: 88,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  @override
  Widget build(BuildContext context) {
    final slots = venue.quickAvailableSlots.take(4).toList();
    return PFCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _thumb(),
              const SizedBox(width: PFSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(venue.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(venue.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: PFColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 5),
                    Text(
                      'Br ${venue.pricePerHour.toStringAsFixed(0)}/hr',
                      style: const TextStyle(
                        color: PFColors.primary, fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (slots.isNotEmpty) ...[
            const SizedBox(height: PFSpacing.md),
            Wrap(
              spacing: PFSpacing.sm,
              runSpacing: PFSpacing.sm,
              children: slots.map((e) {
                final label = e['label']?.toString() ?? '';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: PFColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(PFRadius.sm),
                    border: Border.all(color: PFColors.border),
                  ),
                  child: Text(label,
                      style: const TextStyle(fontSize: 11.5, color: PFColors.textSecondary)),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
