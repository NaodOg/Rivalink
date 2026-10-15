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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final venues = await VenueService.getMyVenues();
    final bookings = await VenueService.getVenueBookings(asOwner: true);
    if (!mounted) return;
    setState(() {
      _venues = venues;
      _bookings = bookings;
      _loading = false;
    });
  }

  double get _revenue => _bookings
      .where((b) => b.status == 'confirmed' || b.status == 'completed')
      .fold(0.0, (sum, b) => sum + b.totalPrice);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PFColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('My venues'),
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
                PFSkeletonCard(height: 80),
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
                  _stats(),
                  const SizedBox(height: PFSpacing.xxl),
                  PFSectionHeader(
                    eyebrow: 'Owner tools',
                    title: 'Bookings',
                    trailing: PFBadge(label: '${_bookings.length}'),
                  ),
                  const SizedBox(height: PFSpacing.md),
                  if (_bookings.isEmpty)
                    PFEmptyState(
                      icon: PFIcons.booking,
                      title: 'No bookings yet',
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

  Widget _stats() {
    return PFCard(
      raised: true,
      child: Row(
        children: [
          _stat('VENUES', '${_venues.length}'),
          _vdiv(),
          _stat('BOOKINGS', '${_bookings.length}'),
          _vdiv(),
          _stat('REVENUE', 'Br ${_revenue.toStringAsFixed(0)}', primary: true),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {bool primary = false}) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          Text(value,
              style: PFType.number.copyWith(
                  fontSize: 18, color: primary ? PFColors.primary : PFColors.text)),
        ],
      ),
    );
  }

  Widget _vdiv() =>
      Container(width: 1, height: 36, margin: const EdgeInsets.symmetric(horizontal: 4), color: PFColors.hairline);

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
                Text(v.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text('${v.city} · Br ${v.pricePerHour.toStringAsFixed(0)}/hr',
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
