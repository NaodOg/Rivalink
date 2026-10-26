import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/rivalink_theme.dart';
import '../../core/data/repositories/app_repository.dart';
import '../../core/data/services/venue_service.dart';
import '../widgets/pf_badge.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_scaffold.dart';

class MyBookingsScreen extends StatefulWidget {
  final AppRepository repo;
  const MyBookingsScreen({super.key, required this.repo});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  List<VenueBooking> _bookings = [];
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
      final b = await widget.repo.getBookings();
      if (!mounted) return;
      setState(() {
        _bookings = b;
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

  Future<void> _pay(VenueBooking booking) async {
    final res = await widget.repo.payVenueBooking(booking.id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final url = res['checkout_url']?.toString() ?? '';
    if (url.isNotEmpty) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
    messenger.showSnackBar(SnackBar(
      content: Text(res['success'] == true
          ? (res['mock'] == true
              ? 'Payment complete (demo mode)'
              : 'Complete the payment in your browser')
          : (res['error'] ?? 'Payment could not be started').toString()),
    ));
    _load();
  }

  Future<void> _cancel(VenueBooking booking) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PFColors.surfaceRaised,
        title: const Text('Cancel this booking?'),
        content: Text(
            '${booking.venueName}\n${booking.date} · ${booking.startTime}–${booking.endTime}'
            '${booking.paymentStatus == 'paid' ? '\n\nThis booking is paid — it will be refunded.' : ''}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel booking',
                  style: TextStyle(color: PFColors.danger))),
        ],
      ),
    );
    if (ok != true) return;
    final res = await widget.repo.cancelVenueBooking(booking.id);
    if (!mounted) return;
    final fee = res['cancellation_fee'];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res['success'] == true
          ? (fee != null && fee.toString() != '0.00'
              ? 'Booking cancelled · late fee Br $fee'
              : 'Booking cancelled')
          : (res['error'] ?? 'Could not cancel').toString()),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return PFScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('My bookings'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: PFColors.primary,
        backgroundColor: PFColors.surfaceRaised,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: PFColors.primary))
            : _error
                ? Center(
                    child: PFEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: "Couldn't load bookings",
                      actionLabel: 'Retry',
                      onAction: _load,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      if (_bookings.isEmpty)
                        const PFEmptyState(
                          icon: Icons.receipt_long_rounded,
                          title: 'No bookings yet',
                          message: 'Reserve a pitch and it will show up here.',
                        )
                      else
                        ..._bookings.map((b) => Padding(
                              padding: const EdgeInsets.only(bottom: PFSpacing.md),
                              child: _bookingCard(b),
                            )),
                    ],
                  ),
      ),
    );
  }

  Widget _bookingCard(VenueBooking b) {
    final (statusLabel, statusColor) = switch (b.status) {
      'confirmed' => ('CONFIRMED', PFColors.success),
      'completed' => ('COMPLETED', PFColors.primary),
      'cancelled' => ('CANCELLED', PFColors.danger),
      _ => ('PENDING', PFColors.warning),
    };
    final paid = b.paymentStatus == 'paid';
    final refunded = b.paymentStatus == 'refunded';
    final canCancel = b.status == 'pending' || b.status == 'confirmed';

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
              PFBadge(label: statusLabel, color: statusColor),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.calendar_month_rounded,
                  size: 14, color: PFColors.textTertiary),
              const SizedBox(width: 5),
              Text(b.date, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 12),
              const Icon(Icons.schedule_rounded,
                  size: 14, color: PFColors.textTertiary),
              const SizedBox(width: 5),
              Text('${b.startTime} – ${b.endTime}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: PFColors.hairline),
          const SizedBox(height: 12),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TOTAL', style: Theme.of(context).textTheme.labelSmall),
                  Text('Br ${b.totalPrice.toStringAsFixed(0)}',
                      style: PFType.number.copyWith(
                          fontSize: 17, color: PFColors.primary)),
                ],
              ),
              const Spacer(),
              if (!paid && !refunded && b.status != 'cancelled') ...[
                PFButton(
                  label: 'Pay',
                  dense: true,
                  expand: false,
                  onTap: () => _pay(b),
                ),
                const SizedBox(width: 8),
              ],
              if (canCancel)
                PFButton(
                  label: 'Cancel',
                  dense: true,
                  expand: false,
                  variant: PFButtonVariant.ghost,
                  onTap: () => _cancel(b),
                ),
            ],
          ),
          if (paid) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 14, color: PFColors.success),
                const SizedBox(width: 5),
                Text('Paid',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: PFColors.success)),
              ],
            ),
          ] else if (refunded) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.undo_rounded, size: 14, color: PFColors.textSecondary),
                const SizedBox(width: 5),
                Text('Refunded',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: PFColors.textSecondary)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
