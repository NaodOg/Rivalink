import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/playfair_theme.dart';
import '../../core/data/services/venue_service.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_scaffold.dart';

class FieldDetailsScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  final int fieldId;
  const FieldDetailsScreen({super.key, required this.session, required this.repo, required this.fieldId});

  @override
  State<FieldDetailsScreen> createState() => _FieldDetailsScreenState();
}

class _FieldDetailsScreenState extends State<FieldDetailsScreen> {
  Venue? _venue;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final venue = await widget.repo.getField(widget.fieldId);
    if (!mounted) return;
    setState(() => _venue = venue);
  }

  Future<void> _book() async {
    if (_venue == null) return;
    final result = await widget.repo.bookField(
      venueId: _venue!.id,
      date: DateTime.now().add(const Duration(days: 1)).toIso8601String().split('T').first,
      start: '17:00',
      end: '18:00',
    );
    if (!mounted) return;
    final ok = result['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Field booked' : (result['error'] ?? 'Booking failed').toString())));
    if (ok) Navigator.pushNamed(context, AppRoutes.myBookings);
  }

  @override
  Widget build(BuildContext context) {
    final venue = _venue;
    return PFScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Field Details'),
      ),
      body: venue == null
          ? const Center(child: CircularProgressIndicator(color: PFColors.accent))
          : ListView(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/images/football_field.avif',
                    height: 210,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 12),
                PFCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(venue.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text('${venue.address}, ${venue.city}', style: const TextStyle(color: PFColors.muted)),
                      const SizedBox(height: 8),
                      Text('Br ${venue.pricePerHour.toStringAsFixed(0)}/hr', style: const TextStyle(color: PFColors.accent, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: venue.quickAvailableSlots.take(4).map((e) => Chip(label: Text((e['label'] ?? '').toString()))).toList()),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                PFButton(label: 'Book 17:00 Slot', onTap: _book),
              ],
            ),
    );
  }
}
