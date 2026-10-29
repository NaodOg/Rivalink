import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/data/media_config.dart';
import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../../core/data/services/venue_service.dart';
import '../../core/data/services/analytics_service.dart';
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
      if (venue != null) {
        AnalyticsService.event('venue_viewed', {
          'venue_id': venue.id,
          'sport': venue.sports.isNotEmpty ? venue.sports.first : '',
          'price': venue.slotPrice,
        });
      }
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
    AnalyticsService.event('booking_sheet_opened', {
      'venue_id': venue.id,
      'price': venue.slotPrice,
    });
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PFColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(PFRadius.xl))),
      builder: (ctx) => _BookingSheet(venue: venue),
    );
    if (!mounted || result == null) return;

    final booking = result['booking'] as VenueBooking?;
    final error = result['error']?.toString();
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (booking == null) return;

    final pay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PFColors.surfaceRaised,
        title: const Text('Slot reserved'),
        content: Text(
            '${booking.venueName}\n${booking.date} · ${booking.startTime}–${booking.endTime}\n'
            'Total Br ${booking.totalPrice.toStringAsFixed(0)}.\n\n'
            'Pay now to confirm instantly, or pay at the venue (the owner still has to accept).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Pay at venue')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Pay now', style: TextStyle(color: PFColors.primary))),
        ],
      ),
    );

    if (pay == true) {
      final token = widget.session.token;
      if (token != null) {
        final res = await widget.repo.payVenueBooking(booking.id);
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final url = res['checkout_url']?.toString() ?? '';
        if (url.isNotEmpty) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
        messenger.showSnackBar(SnackBar(
          content: Text(res['success'] == true
              ? (res['mock'] == true ? 'Payment complete (demo mode)' : 'Complete the payment in your browser')
              : (res['error'] ?? 'Payment could not be started').toString()),
        ));
      }
    }

    if (!mounted) return;
    Navigator.pushNamed(context, AppRoutes.myBookings);
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
            ? CachedNetworkImage(
                imageUrl: img,
                fit: BoxFit.cover,
                placeholder: (_, __) => _bannerPlaceholder(sport),
                errorWidget: (_, __, ___) => _bannerPlaceholder(sport),
              )
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


class _BookingSheet extends StatefulWidget {
  final Venue venue;
  const _BookingSheet({required this.venue});

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  late DateTime _date = DateTime.now();
  List<Map<String, dynamic>> _slots = [];
  int? _selectedIndex;
  bool _loading = true;
  bool _submitting = false;

  String get _dateKey =>
      '${_date.year.toString().padLeft(4, '0')}-'
      '${_date.month.toString().padLeft(2, '0')}-'
      '${_date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    setState(() {
      _loading = true;
      _selectedIndex = null;
    });
    final slots = await VenueService.getSlots(widget.venue.id, _dateKey);
    if (!mounted) return;
    setState(() {
      _slots = slots;
      _loading = false;
      final firstFree = slots.indexWhere((s) => s['status'] == 'free');
      _selectedIndex = firstFree >= 0 ? firstFree : null;
    });
  }

  Map<String, dynamic>? get _selected =>
      _selectedIndex == null ? null : _slots[_selectedIndex!];

  double get _total {
    final s = _selected;
    if (s == null) return 0;
    final start = (s['start'] ?? '').toString().split(':');
    final end = (s['end'] ?? '').toString().split(':');
    if (start.length != 2 || end.length != 2) return widget.venue.slotPrice;
    final hours = (int.tryParse(end[0]) ?? 0) - (int.tryParse(start[0]) ?? 0);
    return widget.venue.slotPrice * (hours / 2).clamp(1, 99);
  }

  Future<void> _submit() async {
    final s = _selected;
    if (s == null) return;
    setState(() => _submitting = true);
    final res = await VenueService.bookVenue(
      venueId: widget.venue.id,
      date: _dateKey,
      startTime: (s['start'] ?? '').toString(),
      endTime: (s['end'] ?? '').toString(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res['success'] == true) {
      Navigator.pop(context, res);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((res['error'] ?? 'Booking failed').toString())));
      _loadSlots();
    }
  }

  @override
  Widget build(BuildContext context) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final today = DateTime.now();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.venue.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall),
                        Text('Pick a day and a 2-hour slot',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 7,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final day = DateTime(today.year, today.month, today.day)
                        .add(Duration(days: i));
                    final selected = i ==
                        DateTime(_date.year, _date.month, _date.day)
                            .difference(DateTime(today.year, today.month, today.day))
                            .inDays;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _date = day);
                        _loadSlots();
                      },
                      child: Container(
                        width: 56,
                        decoration: BoxDecoration(
                          color: selected
                              ? PFColors.primary.withValues(alpha: 0.18)
                              : PFColors.surface,
                          borderRadius: BorderRadius.circular(PFRadius.md),
                          border: Border.all(
                            color: selected ? PFColors.primary : PFColors.border,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(i == 0 ? 'Today' : weekdays[day.weekday - 1],
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? PFColors.primary
                                        : PFColors.textSecondary)),
                            const SizedBox(height: 4),
                            Text('${day.day}',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: selected
                                        ? PFColors.primary
                                        : PFColors.text)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text('AVAILABLE SLOTS', style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: PFColors.primary, strokeWidth: 2)),
                )
              else if (_slots.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text('No slots for this day. Try another date.',
                      style: Theme.of(context).textTheme.bodySmall),
                )
              else
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _slots.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final s = _slots[i];
                      final free = s['status'] == 'free';
                      final reserved = s['status'] == 'reserved';
                      final selected = _selectedIndex == i;
                      return GestureDetector(
                        onTap: free
                            ? () => setState(() => _selectedIndex = i)
                            : null,
                        child: Container(
                          width: 96,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(
                            color: selected
                                ? PFColors.primary.withValues(alpha: 0.16)
                                : PFColors.surface,
                            borderRadius: BorderRadius.circular(PFRadius.md),
                            border: Border.all(
                              color: selected ? PFColors.primary : PFColors.border,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('${s['start']}',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: free
                                          ? (selected
                                              ? PFColors.primary
                                              : PFColors.text)
                                          : PFColors.textTertiary)),
                              Text('to ${s['end']}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: free
                                          ? PFColors.textSecondary
                                          : PFColors.textTertiary)),
                              const SizedBox(height: 6),
                              Text(free
                                  ? 'Available'
                                  : (reserved ? 'Reserved' : 'Booked'),
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: free
                                          ? PFColors.success
                                          : (reserved
                                              ? PFColors.warning
                                              : PFColors.danger))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: PFColors.surface,
                  borderRadius: BorderRadius.circular(PFRadius.md),
                  border: Border.all(color: PFColors.border),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TOTAL', style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 2),
                        Text('Br ${_total.toStringAsFixed(0)}',
                            style: PFType.number.copyWith(
                                fontSize: 20, color: PFColors.primary)),
                      ],
                    ),
                    const Spacer(),
                    Text('${widget.venue.slotPrice.toStringAsFixed(0)}/2h',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              PFButton(
                label: _submitting ? 'Reserving...' : 'Reserve slot',
                icon: Icons.event_available_rounded,
                loading: _submitting,
                onTap: _selected == null ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
