import 'package:flutter/material.dart';

import '../../core/theme/playfair_theme.dart';
import '../../core/data/repositories/app_repository.dart';
import '../../core/data/services/venue_service.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_scaffold.dart';

class MyBookingsScreen extends StatefulWidget {
  final AppRepository repo;
  const MyBookingsScreen({super.key, required this.repo});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  List<VenueBooking> _bookings = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await widget.repo.getBookings();
    if (!mounted) return;
    setState(() => _bookings = b);
  }

  @override
  Widget build(BuildContext context) {
    return PFScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('My Bookings'),
      ),
      body: ListView(
        children: [
          ..._bookings.map((b) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PFCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.venueName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${b.date} • ${b.startTime} - ${b.endTime}', style: const TextStyle(color: PFColors.muted, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('Br ${b.totalPrice.toStringAsFixed(0)}', style: const TextStyle(color: PFColors.accent, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          )),
          if (_bookings.isEmpty) const Text('No bookings yet', style: TextStyle(color: PFColors.muted)),
        ],
      ),
    );
  }
}
