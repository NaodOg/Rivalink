import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/data/services/referee_service.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_badge.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_segmented.dart';
import '../widgets/pf_skeleton.dart';

class RefereeScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const RefereeScreen({super.key, required this.session, required this.repo});

  @override
  State<RefereeScreen> createState() => _RefereeScreenState();
}

class _RefereeScreenState extends State<RefereeScreen> {
  int _tab = 0;
  List<Referee> _referees = [];
  List<RefereeBooking> _bookings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (_tab == 0) {
      final refs = await RefereeService.list();
      if (!mounted) return;
      setState(() {
        _referees = refs;
        _loading = false;
      });
    } else {
      final bookings = await RefereeService.myBookings(asReferee: false);
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _loading = false;
      });
    }
  }

  Future<void> _book(Referee r) async {
    final token = widget.session.token;
    if (token == null) return;
    final matches = await widget.repo.getMyMatches(token, role: 'hosted', status: 'upcoming');
    if (!mounted) return;
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Host a match first to book a referee')));
      return;
    }
    final picked = await showModalBottomSheet<dynamic>(
      context: context,
      backgroundColor: PFColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(PFRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Book ${r.name} for…',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ...matches.take(6).map((m) => ListTile(
                  title: Text(m.title, style: const TextStyle(fontSize: 15)),
                  subtitle: Text(m.formattedDate, style: Theme.of(context).textTheme.bodySmall),
                  onTap: () => Navigator.pop(ctx, m.id),
                )),
            const SizedBox(height: PFSpacing.sm),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final res = await RefereeService.book(refereeId: r.id, matchId: picked as int);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['success'] == true ? 'Referee requested' : (res['error'] ?? 'Failed'))));
    if (res['success'] == true) {
      setState(() => _tab = 1);
      _load();
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
        title: const Text('Referees'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: PFSegmented(
              labels: const ['Find referees', 'My bookings'],
              index: _tab,
              onChanged: (i) {
                setState(() => _tab = i);
                _load();
              },
            ),
          ),
          const SizedBox(height: PFSpacing.md),
          Expanded(
            child: _loading
                ? ListView(
                    padding: const EdgeInsets.all(20),
                    children: const [
                      PFSkeletonCard(height: 92),
                      SizedBox(height: PFSpacing.sm),
                      PFSkeletonCard(height: 92),
                    ],
                  )
                : _tab == 0
                    ? _refereeList()
                    : _bookingList(),
          ),
        ],
      ),
    );
  }

  Widget _refereeList() {
    if (_referees.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 40),
        PFEmptyState(
          icon: PFIcons.referee,
          title: 'No referees available',
          message: 'Verified referees will appear here.',
        ),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemCount: _referees.length,
      separatorBuilder: (_, __) => const SizedBox(height: PFSpacing.sm),
      itemBuilder: (_, i) => _refereeCard(_referees[i]),
    );
  }

  Widget _refereeCard(Referee r) {
    return PFCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    const SizedBox(width: 8),
                    PFBadge(
                      label: '★ ${r.averageRating.toStringAsFixed(1)}',
                      color: PFColors.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${r.sports.isEmpty ? 'Multi-sport' : r.sports.join(', ')} · ${r.experienceYears}y'
                  '${r.location.isNotEmpty ? ' · ${r.location}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text('Br ${r.hourlyRate.toStringAsFixed(0)}/hr',
                    style: const TextStyle(
                        color: PFColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: PFSpacing.sm),
          PFButton(label: 'Book', dense: true, expand: false, onTap: () => _book(r)),
        ],
      ),
    );
  }

  Widget _bookingList() {
    if (_bookings.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 40),
        PFEmptyState(icon: PFIcons.booking, title: 'No referee bookings'),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemCount: _bookings.length,
      separatorBuilder: (_, __) => const SizedBox(height: PFSpacing.sm),
      itemBuilder: (_, i) {
        final b = _bookings[i];
        return PFCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.refereeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(b.matchTitle ?? 'Match',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              PFBadge(
                label: b.status.toUpperCase(),
                color: b.status == 'accepted'
                    ? PFColors.primary
                    : (b.status == 'declined' ? PFColors.danger : PFColors.warning),
              ),
            ],
          ),
        );
      },
    );
  }
}
