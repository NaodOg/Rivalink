import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/data/media_config.dart';
import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../../core/data/services/venue_service.dart';
import '../widgets/pf_badge.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_sport_tile.dart';

class FieldDetailsScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  final int fieldId;
  const FieldDetailsScreen({
    super.key,
    required this.session,
    required this.repo,
    required this.fieldId,
  });

  @override
  State<FieldDetailsScreen> createState() => _FieldDetailsScreenState();
}

class _FieldDetailsScreenState extends State<FieldDetailsScreen> {
  Venue? _venue;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final venue = await widget.repo.getField(widget.fieldId);
      if (!mounted) return;
      setState(() {
        _venue = venue;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _book() async {
    final venue = _venue;
    if (venue == null) return;
    final slot = venue.quickAvailableSlots.isNotEmpty ? venue.quickAvailableSlots.first : null;
    final result = await widget.repo.bookField(
      venueId: venue.id,
      date: DateTime.now().add(const Duration(days: 1)).toIso8601String().split('T').first,
          start: slot?['start_time']?.toString() ?? '17:00',
          end: slot?['end_time']?.toString() ?? '19:00',
    );
    if (!mounted) return;
    final ok = result['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Field booked' : (result['error'] ?? 'Booking failed').toString())),
    );
    if (ok) Navigator.pushNamed(context, AppRoutes.myBookings);
  }

  @override
  Widget build(BuildContext context) {
    final venue = _venue;
    return Scaffold(
      backgroundColor: PFColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Venue'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PFColors.primary))
          : _error
              ? Center(
                  child: PFEmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: "Couldn't load venue",
                    actionLabel: 'Retry',
                    onAction: _load,
                  ),
                )
              : venue == null
                  ? const Center(
                      child: PFEmptyState(icon: Icons.search_off_rounded, title: 'Venue not found'))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      children: [
                        _banner(venue),
                        const SizedBox(height: PFSpacing.lg),
                        Text(venue.name, style: Theme.of(context).textTheme.displaySmall),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.place_outlined, size: 14, color: PFColors.textSecondary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('${venue.address}, ${venue.city}',
                                  style: Theme.of(context).textTheme.bodyMedium),
                            ),
                          ],
                        ),
                        const SizedBox(height: PFSpacing.lg),
                        _priceCard(venue),
                        const SizedBox(height: PFSpacing.lg),
                        if (venue.quickAvailableSlots.isNotEmpty) ...[
                          Text('AVAILABLE TODAY', style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: PFSpacing.md),
                          Wrap(
                            spacing: PFSpacing.sm,
                            runSpacing: PFSpacing.sm,
                            children: venue.quickAvailableSlots
                                .take(4)
                                .map((e) => PFBadge(
                                      label: (e['label'] ?? '').toString(),
                                      color: PFColors.primary,
                                    ))
                                .toList(),
                          ),
                        ],
                      ],
                    ),
      bottomNavigationBar: venue != null ? _bottomBar(venue) : null,
    );
  }

  Widget _banner(Venue venue) {
    final img = MediaConfig.resolve(venue.primaryImage);
    final hasImg = img != null && img.isNotEmpty;
    final sport = venue.sports.isNotEmpty ? venue.sports.first : 'other';
    return ClipRRect(
      borderRadius: BorderRadius.circular(PFRadius.xl),
      child: SizedBox(
        height: 200,
        child: hasImg
            ? Image.network(img, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _bannerPlaceholder(sport))
            : _bannerPlaceholder(sport),
      ),
    );
  }

  Widget _bannerPlaceholder(String sport) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [PFColors.surfaceRaised, PFColors.surface],
        ),
      ),
      alignment: Alignment.center,
      child: PFSportTile(sport: sport, size: 96),
    );
  }

  Widget _priceCard(Venue venue) {
    return PFCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('2-HOUR SLOT', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 6),
                Text('Br ${venue.slotPrice.toStringAsFixed(0)}',
                    style: PFType.number.copyWith(fontSize: 22, color: PFColors.primary)),
              ],
            ),
          ),
          Container(width: 1, height: 42, color: PFColors.hairline),
          const SizedBox(width: PFSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CAPACITY', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 6),
                Text('${venue.capacity}',
                    style: PFType.number.copyWith(fontSize: 22)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(Venue venue) {
    return Container(
      decoration: const BoxDecoration(
        color: PFColors.surface,
        border: Border(top: BorderSide(color: PFColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Br ${venue.slotPrice.toStringAsFixed(0)}/2h',
                      style: PFType.number.copyWith(fontSize: 18, color: PFColors.primary)),
                  Text('2-hour slot', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              const SizedBox(width: PFSpacing.lg),
              Expanded(
                child: PFButton(
                  label: 'Book a slot',
                  icon: PFIcons.booking,
                  onTap: _book,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
