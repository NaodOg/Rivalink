import 'package:cached_network_image/cached_network_image.dart';
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
      width: 76,
      height: 64,
      decoration: BoxDecoration(
        color: PFColors.surfaceRaised,
        borderRadius: BorderRadius.circular(PFRadius.md),
        border: Border.all(color: PFColors.border),
      ),
      alignment: Alignment.center,
      child: Icon(PFIcons.venue, color: PFColors.primary, size: 24),
    );
  }

  Widget _thumb() {
    final img = MediaConfig.resolve(venue.primaryImage);
    if (img != null && img.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(PFRadius.md),
        child: CachedNetworkImage(
          imageUrl: img,
          width: 76,
          height: 64,
          fit: BoxFit.cover,
          placeholder: (_, __) => _placeholder(),
          errorWidget: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  @override
  Widget build(BuildContext context) {
    final slots = venue.quickAvailableSlots.take(2).toList();
    return PFCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(venue.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: PFColors.textSecondary, fontSize: 11.5)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Br ${venue.slotPrice.toStringAsFixed(0)}/2h',
                          style: const TextStyle(
                            color: PFColors.primary, fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        if (venue.verificationStatus == 'verified')
                          const Icon(Icons.verified_rounded,
                              size: 13, color: PFColors.success),
                        if (venue.averageRating > 0) ...[
                          const SizedBox(width: 3),
                          const Icon(Icons.star_rounded, size: 13, color: PFColors.gold),
                          const SizedBox(width: 2),
                          Text(venue.averageRating.toStringAsFixed(1),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: PFColors.text)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (slots.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < slots.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: PFColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(PFRadius.sm),
                        border: Border.all(color: PFColors.border),
                      ),
                      child: Text(
                        slots[i]['label']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10.5, color: PFColors.textSecondary),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Text(
                  '${venue.quickAvailableSlots.length} free',
                  style: TextStyle(
                    color: venue.quickAvailableSlots.length <= 2
                        ? PFColors.warning
                        : PFColors.success,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
