import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/data/services/venue_service.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_avatar.dart';
import '../widgets/pf_badge.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_section_header.dart';
import '../widgets/pf_segmented.dart';
import '../widgets/pf_skeleton.dart';

class VenueDashboardScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const VenueDashboardScreen({super.key, required this.session, required this.repo});

  @override
  State<VenueDashboardScreen> createState() => _VenueDashboardScreenState();
}

class _VenueDashboardScreenState extends State<VenueDashboardScreen> {
  List<Venue> _venues = [];
  List<VenueBooking> _bookings = [];
  Map<String, dynamic> _schedule = {};
  Map<String, dynamic> _revenue = {};
  bool _loading = true;

  int? _venueId;
  String _selectedDate = '';
  String _scope = 'upcoming';
  String _statusFilter = 'all';
  static const _statusOptions = ['all', 'pending', 'confirmed', 'completed', 'cancelled'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> get _days =>
      ((_schedule['days'] as List?) ?? []).cast<Map<String, dynamic>>();

  Map<String, dynamic>? get _selectedDay {
    if (_days.isEmpty) return null;
    return _days.firstWhere(
      (d) => d['date'] == _selectedDate,
      orElse: () => _days.first,
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final venues = await VenueService.getMyVenues();
    final venueId = _venueId ?? (venues.isNotEmpty ? venues.first.id : null);

    final results = await Future.wait([
      VenueService.getVenueBookings(
        asOwner: true,
        venueId: venueId,
        status: _statusFilter == 'all' ? null : _statusFilter,
        scope: _scope == 'all' ? null : _scope,
      ),
      venueId == null ? Future.value(<String, dynamic>{}) : VenueService.getSchedule(venueId),
      VenueService.getRevenue(),
    ]);

    if (!mounted) return;
    setState(() {
      _venues = venues;
      _venueId = venueId;
      _bookings = results[0] as List<VenueBooking>;
      _schedule = results[1] as Map<String, dynamic>;
      _revenue = results[2] as Map<String, dynamic>;
      if (_days.isNotEmpty && !_days.any((d) => d['date'] == _selectedDate)) {
        _selectedDate = _days.first['date'] as String;
      }
      _loading = false;
    });
  }

  Future<void> _selectVenue(int id) async {
    setState(() => _venueId = id);
    await _load();
  }

  Future<void> _setStatus(VenueBooking b, String status) async {
    final res = await VenueService.updateBookingStatus(bookingId: b.id, status: status);
    if (!mounted) return;
    if (res['success'] == true) {
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['error']?.toString() ?? 'Failed')));
    }
  }

  double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PFColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Venue dashboard'),
        actions: [
          IconButton(
            tooltip: 'Add venue',
            icon: Icon(PFIcons.add),
            onPressed: () async {
              final added = await Navigator.pushNamed(context, '/add-field');
              if (added == true) _load();
            },
          ),
        ],
      ),
      body: _loading
          ? ListView(
              padding: const EdgeInsets.all(20),
              children: const [
                PFSkeleton(width: double.infinity, height: 92, radius: PFRadius.lg),
                SizedBox(height: PFSpacing.md),
                PFSkeletonCard(height: 120),
                SizedBox(height: PFSpacing.sm),
                PFSkeletonCard(height: 80),
              ],
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: PFColors.primary,
              backgroundColor: PFColors.surfaceRaised,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  _revenueCard(),
                  const SizedBox(height: PFSpacing.xxl),
                  if (_venues.length > 1) ...[
                    PFSectionHeader(eyebrow: 'Listing', title: 'Venue'),
                    const SizedBox(height: PFSpacing.md),
                    _venueChips(),
                    const SizedBox(height: PFSpacing.xxl),
                  ],
                  PFSectionHeader(eyebrow: 'Availability', title: 'Schedule'),
                  const SizedBox(height: PFSpacing.md),
                  if (_days.isEmpty)
                    PFEmptyState(
                      icon: PFIcons.booking,
                      title: 'No schedule',
                      message: 'Add a venue to see its day-by-day slots.',
                    )
                  else ...[
                    _weekStrip(),
                    const SizedBox(height: PFSpacing.lg),
                    _daySlots(),
                  ],
                  const SizedBox(height: PFSpacing.xxl),
                  PFSectionHeader(
                    eyebrow: 'Owner tools',
                    title: 'Bookings',
                    trailing: PFBadge(label: '${_bookings.length}'),
                  ),
                  const SizedBox(height: PFSpacing.md),
                  _bookingFilters(),
                  const SizedBox(height: PFSpacing.md),
                  if (_bookings.isEmpty)
                    PFEmptyState(
                      icon: PFIcons.booking,
                      title: 'No bookings',
                      message: 'Player bookings will appear here to confirm.',
                    )
                  else
                    ..._bookings.map((b) => Padding(
                          padding: const EdgeInsets.only(bottom: PFSpacing.sm),
                          child: _bookingCard(b),
                        )),
                  const SizedBox(height: PFSpacing.xxl),
                  PFSectionHeader(eyebrow: 'Listings', title: 'Your venues'),
                  const SizedBox(height: PFSpacing.md),
                  if (_venues.isEmpty)
                    PFEmptyState(
                      icon: PFIcons.venue,
                      title: 'No venues yet',
                      message: 'Add a venue to start taking bookings.',
                    )
                  else
                    ..._venues.map((v) => Padding(
                          padding: const EdgeInsets.only(bottom: PFSpacing.sm),
                          child: _venueCard(v),
                        )),
                ],
              ),
            ),
    );
  }

  // ── Revenue ──
  Widget _revenueCard() {
    final collected = _num(_revenue['total_collected']);
    final pending = _num(_revenue['total_pending']);
    final months = ((_revenue['by_month'] as List?) ?? []).cast<Map<String, dynamic>>();

    return PFCard(
      raised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _stat('COLLECTED', 'Br ${collected.toStringAsFixed(0)}', primary: true)),
              _vdiv(),
              Expanded(child: _stat('PENDING', 'Br ${pending.toStringAsFixed(0)}')),
              _vdiv(),
              Expanded(child: _stat('VENUES', '${_venues.length}')),
            ],
          ),
          if (months.isNotEmpty) ...[
            const SizedBox(height: PFSpacing.lg),
            const Divider(color: PFColors.hairline, height: 1),
            const SizedBox(height: PFSpacing.md),
            ...months.take(4).map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('${m['month']}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                      Text('${m['bookings']} bookings · ',
                          style: Theme.of(context).textTheme.bodySmall),
                      Text('Br ${_num(m['collected']).toStringAsFixed(0)}',
                          style: PFType.number.copyWith(fontSize: 13, color: PFColors.primary)),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {bool primary = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 6),
        Text(value,
            style: PFType.number.copyWith(
                fontSize: 17, color: primary ? PFColors.primary : PFColors.text)),
      ],
    );
  }

  Widget _vdiv() =>
      Container(width: 1, height: 36, margin: const EdgeInsets.symmetric(horizontal: 8), color: PFColors.hairline);

  // ── Venue chips ──
  Widget _venueChips() {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _venues.length,
        separatorBuilder: (_, __) => const SizedBox(width: PFSpacing.sm),
        itemBuilder: (_, i) {
          final v = _venues[i];
          final active = v.id == _venueId;
          return GestureDetector(
            onTap: () => _selectVenue(v.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? PFColors.primary : PFColors.surfaceRaised,
                borderRadius: BorderRadius.circular(PFRadius.pill),
                border: Border.all(color: active ? PFColors.primary : PFColors.border),
              ),
              child: Text(
                v.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active ? PFColors.onPrimary : PFColors.text,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Week strip ──
  Widget _weekStrip() {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _days.length,
        separatorBuilder: (_, __) => const SizedBox(width: PFSpacing.sm),
        itemBuilder: (_, i) {
          final d = _days[i];
          final active = d['date'] == _selectedDay?['date'];
          final date = DateTime.tryParse(d['date']?.toString() ?? '');
          final booked = (d['booked'] ?? 0) as int;
          final free = (d['free'] ?? 0) as int;
          return GestureDetector(
            onTap: () => setState(() => _selectedDate = d['date'] as String),
            child: Container(
              width: 74,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: active ? PFColors.primary : PFColors.surfaceRaised,
                borderRadius: BorderRadius.circular(PFRadius.lg),
                border: Border.all(color: active ? PFColors.primary : PFColors.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${d['weekday']}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: active ? PFColors.onPrimary : PFColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(date == null ? '--' : '${date.day}',
                      style: PFType.number.copyWith(
                          fontSize: 20,
                          color: active ? PFColors.onPrimary : PFColors.text)),
                  const SizedBox(height: 6),
                  Text('$booked booked',
                      style: TextStyle(
                          fontSize: 10,
                          color: active ? PFColors.onPrimary : PFColors.textTertiary)),
                  Text('$free free',
                      style: TextStyle(
                          fontSize: 10,
                          color: active ? PFColors.onPrimary : PFColors.textTertiary)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _daySlots() {
    final day = _selectedDay;
    if (day == null) return const SizedBox.shrink();
    final slots = ((day['slots'] as List?) ?? []).cast<Map<String, dynamic>>();
    final venueName = _schedule['venue']?['name']?.toString() ?? '';

    return PFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${day['date']} · $venueName',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              PFBadge(label: 'Br ${_num(day['revenue']).toStringAsFixed(0)}', color: PFColors.primary),
            ],
          ),
          const SizedBox(height: PFSpacing.md),
          ...slots.map((s) {
            final booked = s['status'] == 'booked';
            final b = (s['booking'] as Map?)?.cast<String, dynamic>();
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text('${s['start']}–${s['end']}',
                        style: PFType.number.copyWith(fontSize: 13)),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: booked ? PFColors.primary.withValues(alpha: 0.14) : PFColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(PFRadius.md),
                        border: Border.all(
                            color: booked ? PFColors.primary : PFColors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(booked ? PFIcons.booking : PFIcons.add,
                              size: 15,
                              color: booked ? PFColors.primary : PFColors.textTertiary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              booked
                                  ? '${b?['match_title'] ?? b?['booked_by'] ?? 'Booked'}'
                                  : 'Free',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: booked ? FontWeight.w700 : FontWeight.w500,
                                color: booked ? PFColors.text : PFColors.textTertiary,
                              ),
                            ),
                          ),
                          if (booked)
                            PFBadge(
                              label: (b?['status'] ?? '').toString().toUpperCase(),
                              color: b?['status'] == 'confirmed'
                                  ? PFColors.primary
                                  : PFColors.warning,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Booking filters ──
  Widget _bookingFilters() {
    return Column(
      children: [
        PFSegmented(
          labels: const ['Upcoming', 'Past', 'All'],
          index: _scope == 'upcoming' ? 0 : (_scope == 'past' ? 1 : 2),
          onChanged: (i) {
            setState(() => _scope = ['upcoming', 'past', 'all'][i]);
            _load();
          },
        ),
        const SizedBox(height: PFSpacing.sm),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _statusOptions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final s = _statusOptions[i];
              final active = _statusFilter == s;
              return GestureDetector(
                onTap: () {
                  setState(() => _statusFilter = s);
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? PFColors.primary : PFColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(PFRadius.pill),
                    border: Border.all(color: active ? PFColors.primary : PFColors.border),
                  ),
                  child: Text(
                    s[0].toUpperCase() + s.substring(1),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: active ? PFColors.onPrimary : PFColors.textSecondary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _bookingCard(VenueBooking b) {
    final pending = b.status == 'pending';
    return PFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(b.venueName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              PFBadge(
                label: b.status.toUpperCase(),
                color: b.status == 'confirmed'
                    ? PFColors.primary
                    : (b.status == 'cancelled' ? PFColors.danger : PFColors.warning),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('${b.date} · ${b.startTime}–${b.endTime} · Br ${b.totalPrice.toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.bodySmall),
          if (pending) ...[
            const SizedBox(height: PFSpacing.md),
            Row(
              children: [
                Expanded(
                  child: PFButton(
                    label: 'Confirm',
                    dense: true,
                    onTap: () => _setStatus(b, 'confirmed'),
                  ),
                ),
                const SizedBox(width: PFSpacing.sm),
                Expanded(
                  child: PFButton(
                    label: 'Decline',
                    dense: true,
                    variant: PFButtonVariant.secondary,
                    onTap: () => _setStatus(b, 'cancelled'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _venueCard(Venue v) {
    final verified = v.verificationStatus == 'verified';
    return PFCard(
      onTap: () => Navigator.pushNamed(context, '/field-details', arguments: v.id),
      child: Row(
        children: [
          PFAvatar(name: v.name, size: 44),
          const SizedBox(width: PFSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(v.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    if (verified) ...[
                      const SizedBox(width: 6),
                      Icon(PFIcons.verified, size: 14, color: PFColors.primary),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text('${v.city} · Br ${v.slotPrice.toStringAsFixed(0)}/2h',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          PFBadge(
            label: v.isAvailable ? 'OPEN' : 'CLOSED',
            color: v.isAvailable ? PFColors.primary : PFColors.textSecondary,
          ),
        ],
      ),
    );
  }
}
