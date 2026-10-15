import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';
import '../../core/data/repositories/app_repository.dart';
import '../../core/data/services/venue_service.dart';
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
    setState(() { _loading = true; _error = false; });
    try {
      final b = await widget.repo.getBookings();
      if (!mounted) return;
      setState(() {
        _bookings = b;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = true; });
    }
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
      body: _loading
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
                  children: [
                    ..._bookings.map((b) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: PFCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.venueName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            const SizedBox(height: 4),
                            Text('${b.date} • ${b.startTime} - ${b.endTime}', style: const TextStyle(color: PFColors.textSecondary, fontSize: 12)),
                            const SizedBox(height: 6),
                            Text('Br ${b.totalPrice.toStringAsFixed(0)}', style: const TextStyle(color: PFColors.primary, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    )),
                    if (_bookings.isEmpty)
                      const PFEmptyState(
                        icon: Icons.receipt_long_rounded,
                        title: 'No bookings yet',
                        message: 'Reserve a pitch and it will show up here.',
                      ),
                  ],
                ),
    );
  }
}
