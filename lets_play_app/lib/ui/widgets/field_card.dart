import 'package:flutter/material.dart';

import '../../core/theme/playfair_theme.dart';
import '../../core/data/services/venue_service.dart';
import 'pf_card.dart';

class FieldCard extends StatelessWidget {
  final Venue venue;
  final VoidCallback? onTap;

  const FieldCard({super.key, required this.venue, this.onTap});

  @override
  Widget build(BuildContext context) {
    return PFCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset('assets/images/football_field.avif', width: 90, height: 74, fit: BoxFit.cover),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(venue.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(venue.city, style: const TextStyle(color: PFColors.muted, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('Br ${venue.pricePerHour.toStringAsFixed(0)}/hr', style: const TextStyle(color: PFColors.accent, fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: venue.quickAvailableSlots.take(4).map((e) {
              final label = e['label']?.toString() ?? '';
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: PFColors.cardSoft, borderRadius: BorderRadius.circular(10)),
                child: Text(label, style: const TextStyle(fontSize: 11)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
