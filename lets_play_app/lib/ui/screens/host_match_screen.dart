import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/data/services/venue_service.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_skeleton.dart';
import '../widgets/pf_sport_tile.dart';

class HostMatchScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const HostMatchScreen({super.key, required this.session, required this.repo});

  @override
  State<HostMatchScreen> createState() => _HostMatchScreenState();
}

class _HostMatchScreenState extends State<HostMatchScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _price = TextEditingController();
  final _max = TextEditingController();
  final _min = TextEditingController();

  List<Venue> _venues = [];
  Venue? _venue;
  Map<String, dynamic> _availability = {};
  bool _loadingSlots = false;
  String _slotDate = '';
  bool _slotPicked = false;

  int get _playerCount {
    final minP = int.tryParse(_min.text) ?? 0;
    if (minP > 0) return minP;
    return int.tryParse(_max.text) ?? 0;
  }

  double get _computedShare {
    final venue = _venue;
    if (venue == null || _playerCount <= 0) return 0;
    return venue.slotPrice / _playerCount;
  }

  /// Keep the per-player fee in step with field price ÷ players.
  void _syncPrice() {
    if (_computedShare > 0) {
      _price.text = _computedShare.toStringAsFixed(0);
    }
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> get _availDays =>
      ((_availability['days'] as List?) ?? []).cast<Map<String, dynamic>>();

  Map<String, dynamic>? get _selectedDayData {
    if (_availDays.isEmpty) return null;
    return _availDays.firstWhere((d) => d['date'] == _slotDate, orElse: () => _availDays.first);
  }

  String get _timeLabel =>
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  static const _sports = ['soccer', 'basketball', 'tennis'];
  static const _types = ['5v5', '7v7', '11v11'];
  static const _skills = [
    ('any', 'Any'),
    ('beginner', 'Beginner'),
    ('intermediate', 'Intermediate'),
    ('advanced', 'Advanced'),
  ];

  String _sport = 'soccer';
  String _type = '5v5';
  String _skill = 'any';
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 19, minute: 0);
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadVenues();
  }

  Future<void> _loadVenues() async {
    final venues = await VenueService.getVenues();
    if (!mounted) return;
    setState(() => _venues = venues);
  }

  Future<void> _loadAvailability() async {
    final venue = _venue;
    if (venue == null) return;
    setState(() => _loadingSlots = true);
    final today = DateTime.now();
    final from = _dateKeyOf(today);
    final to = _dateKeyOf(today.add(const Duration(days: 13)));
    final data = await VenueService.getAvailabilityRange(venue.id, from, to);
    if (!mounted) return;
    setState(() {
      _availability = data;
      _slotDate = from;
      _loadingSlots = false;
    });
  }

  String _dateKeyOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickVenue() async {
    if (_venues.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No fields available yet.')));
      return;
    }
    final picked = await _venueSheet();
    if (picked != null) {
      setState(() {
        _venue = picked;
        _location.text = '${picked.name}, ${picked.city}';
      });
      _syncPrice();
      _loadAvailability();
    }
  }

  Future<Venue?> _venueSheet() {
    String query = '';
    return showModalBottomSheet<Venue>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PFColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(PFRadius.xl)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final q = query.toLowerCase();
          final list = _venues.where((v) {
            if (q.isEmpty) return true;
            return v.name.toLowerCase().contains(q) ||
                v.city.toLowerCase().contains(q) ||
                v.sportsString.toLowerCase().contains(q);
          }).toList();

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.7,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Choose a field',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: TextField(
                        autofocus: false,
                        onChanged: (v) => setSheet(() => query = v),
                        decoration: const InputDecoration(
                          hintText: 'Search by name, city or sport',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    Expanded(
                      child: list.isEmpty
                          ? const Center(
                              child: Text('No fields match your search',
                                  style: TextStyle(color: PFColors.textTertiary)))
                          : ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (_, i) {
                                final v = list[i];
                                return ListTile(
                                  leading: Icon(PFIcons.venue, color: PFColors.primary),
                                  title: Text(v.name),
                                  subtitle: Text(
                                      '${v.city} · Br ${v.slotPrice.toStringAsFixed(0)}/2h'),
                                  trailing: v.verificationStatus == 'verified'
                                      ? Icon(PFIcons.verified,
                                          size: 16, color: PFColors.primary)
                                      : null,
                                  onTap: () => Navigator.pop(ctx, v),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _price.dispose();
    _max.dispose();
    _min.dispose();
    super.dispose();
  }

  DateTime get _scheduled => DateTime(
      _date.year, _date.month, _date.day, _time.hour, _time.minute);

  Future<void> _submit() async {
    if (_submitting) return;
    final token = widget.session.token;
    if (token == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please log in first.')));
      return;
    }
    if (_title.text.trim().isEmpty || _venue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Title and field are required.')));
      return;
    }
    setState(() => _submitting = true);
    final result = await widget.repo.createMatch(
      token: token,
      title: _title.text.trim(),
      sport: _sport,
      description:
          '$_type${_description.text.trim().isEmpty ? '' : ' • ${_description.text.trim()}'}',
      location: _venue == null ? _location.text.trim() : '${_venue!.name}, ${_venue!.city}',
      dateTime: _scheduled,
      maxPlayers: int.tryParse(_max.text) ?? 10,
      minPlayers: int.tryParse(_min.text) ?? 0,
      price: double.tryParse(_price.text) ?? 0,
      skillLevel: _skill,
      venueId: _venue?.id,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result['success'] == true) {
      Navigator.pop(context, true);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result['error']?.toString() ?? 'Failed to create match')),
    );
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
        title: const Text('Host a match'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text('Set up your game',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text('Pick a sport, lock your venue and fill the squad.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: PFSpacing.xl),
          _label('Sport'),
          const SizedBox(height: PFSpacing.sm),
          Row(
            children: _sports.map((s) {
              final active = _sport == s;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: s == _sports.last ? 0 : PFSpacing.sm),
                  child: GestureDetector(
                    onTap: () => setState(() => _sport = s),
                    child: AnimatedContainer(
                      duration: PFMotion.fast,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: active
                            ? PFSport.color(s).withValues(alpha: 0.16)
                            : PFColors.surface,
                        borderRadius: BorderRadius.circular(PFRadius.md),
                        border: Border.all(
                            color: active ? PFSport.color(s) : PFColors.border),
                      ),
                      child: Column(
                        children: [
                          PFSportTile(sport: s, size: 34),
                          const SizedBox(height: 6),
                          Text(
                            s[0].toUpperCase() + s.substring(1),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: active ? PFColors.text : PFColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: PFSpacing.lg),
          _label('Format'),
          const SizedBox(height: PFSpacing.sm),
          _SegmentedRow(
            options: _types,
            selected: _type,
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: PFSpacing.lg),
          _label('Skill level'),
          const SizedBox(height: PFSpacing.sm),
          Wrap(
            spacing: PFSpacing.sm,
            runSpacing: PFSpacing.sm,
            children: _skills.map((s) {
              return ChoiceChip(
                label: Text(s.$2),
                selected: _skill == s.$1,
                onSelected: (_) => setState(() => _skill = s.$1),
              );
            }).toList(),
          ),
          const SizedBox(height: PFSpacing.lg),
          PFCard(
            child: Column(
              children: [
                _field('Match title', TextField(
                  controller: _title,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'e.g. Sunday 5v5 at Bole'),
                )),
                const SizedBox(height: PFSpacing.md),
                _field('Field', GestureDetector(
                  onTap: _pickVenue,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: PFColors.surface,
                      borderRadius: BorderRadius.circular(PFRadius.md),
                      border: Border.all(
                          color: _venue == null ? PFColors.border : PFColors.primary),
                    ),
                    child: Row(
                      children: [
                        Icon(PFIcons.venue,
                            size: 17,
                            color: _venue == null
                                ? PFColors.textSecondary
                                : PFColors.primary),
                        const SizedBox(width: PFSpacing.sm),
                        Expanded(
                          child: Text(
                            _venue == null
                                ? 'Pick a field'
                                : '${_venue!.name} · ${_venue!.city}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              color: _venue == null
                                  ? PFColors.textTertiary
                                  : PFColors.text,
                            ),
                          ),
                        ),
                        Icon(PFIcons.chevron, size: 14, color: PFColors.textSecondary),
                      ],
                    ),
                  ),
                )),
                const SizedBox(height: PFSpacing.md),
                _field('Notes', TextField(
                  controller: _description,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      hintText: 'Skill level, kit, rules…'),
                )),
              ],
            ),
          ),
          const SizedBox(height: PFSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _field('Min players', TextField(
                      controller: _min,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _syncPrice(),
                      decoration: const InputDecoration(hintText: 'e.g. 8'),
                    )),
                    const SizedBox(height: PFSpacing.md),
                    _field('Max players', TextField(
                      controller: _max,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _syncPrice(),
                      decoration: const InputDecoration(hintText: '10'),
                    )),
                  ],
                ),
              ),
              const SizedBox(width: PFSpacing.md),
              Expanded(
                child: _field('Fee / player (Br)', TextField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '0'),
                )),
              ),
            ],
          ),
          if (_venue != null) ...[
            const SizedBox(height: 6),
            Text(
              'Share of the field: Br ${_venue!.slotPrice.toStringAsFixed(0)} ÷ '
              '$_playerCount players = Br ${_computedShare.toStringAsFixed(0)} each',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_venue != null) ...[
            const SizedBox(height: PFSpacing.lg),
            _label('Availability'),
            const SizedBox(height: 4),
            Text(
              _slotPicked
                  ? 'Kickoff: ${_date.day}/${_date.month} · $_timeLabel'
                  : 'Pick a day, then tap an available slot to set kickoff.',
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: _slotPicked ? PFColors.primary : PFColors.textSecondary,
                    fontWeight: _slotPicked ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
            const SizedBox(height: PFSpacing.sm),
            _availabilityCalendar(),
          ],
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: PFColors.surface,
          border: Border(top: BorderSide(color: PFColors.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: PFButton(
              label: 'Create match',
              loading: _submitting,
              onTap: _submit,
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall);

  Widget _availabilityCalendar() {
    if (_loadingSlots) {
      return const PFSkeletonCard(height: 140);
    }
    if (_availDays.isEmpty) {
      return Text('No slots published for this field.',
          style: Theme.of(context).textTheme.bodySmall);
    }

    final day = _selectedDayData;
    final slots = ((day?['slots'] as List?) ?? []).cast<Map<String, dynamic>>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _availDays.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final d = _availDays[i];
              final active = d['date'] == day?['date'];
              final date = DateTime.tryParse(d['date']?.toString() ?? '');
              final free = (d['free'] ?? 0) as int;
              final full = free == 0;
              return GestureDetector(
                onTap: () {
                  final parsed = DateTime.tryParse(d['date']?.toString() ?? '');
                  setState(() {
                    _slotDate = d['date'] as String;
                    if (parsed != null) _date = parsed;
                    _slotPicked = false;
                  });
                },
                child: Container(
                  width: 66,
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
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: active ? PFColors.onPrimary : PFColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text(date == null ? '--' : '${date.day}',
                          style: PFType.number.copyWith(
                              fontSize: 19,
                              color: active ? PFColors.onPrimary : PFColors.text)),
                      const SizedBox(height: 3),
                      Text(full ? 'full' : '$free free',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: active
                                  ? PFColors.onPrimary
                                  : (full ? PFColors.danger : PFColors.textTertiary))),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: PFSpacing.md),
        ...slots.map((s) {
          final booked = s['status'] == 'booked';
          final start = s['start']?.toString() ?? '';
          final selected = !booked && _timeLabel == start;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: booked
                  ? null
                  : () {
                      final parts = start.split(':');
                      if (parts.length == 2) {
                        setState(() {
                          _time = TimeOfDay(
                              hour: int.tryParse(parts[0]) ?? 19,
                              minute: int.tryParse(parts[1]) ?? 0);
                          _slotPicked = true;
                        });
                      }
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: booked
                      ? PFColors.surface
                      : (selected ? PFColors.primary : PFColors.surfaceRaised),
                  borderRadius: BorderRadius.circular(PFRadius.md),
                  border: Border.all(
                      color: booked
                          ? PFColors.hairline
                          : (selected ? PFColors.primary : PFColors.border)),
                ),
                child: Row(
                  children: [
                    Icon(
                      booked ? Icons.close_rounded : Icons.check_circle_outline_rounded,
                      size: 18,
                      color: booked
                          ? PFColors.danger
                          : (selected ? PFColors.onPrimary : PFColors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('$start–${s['end']}',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: booked
                                  ? PFColors.textTertiary
                                  : (selected ? PFColors.onPrimary : PFColors.text))),
                    ),
                    Text(
                      booked ? 'BOOKED' : 'AVAILABLE',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: booked
                              ? PFColors.danger
                              : (selected ? PFColors.onPrimary : PFColors.primary)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _field(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _SegmentedRow extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;
  const _SegmentedRow(
      {required this.options, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: PFColors.surface,
        borderRadius: BorderRadius.circular(PFRadius.pill),
        border: Border.all(color: PFColors.border),
      ),
      child: Row(
        children: options.map((o) {
          final active = o == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(o),
              child: AnimatedContainer(
                duration: PFMotion.fast,
                decoration: BoxDecoration(
                  color: active ? PFColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(PFRadius.pill),
                ),
                alignment: Alignment.center,
                child: Text(o,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: active ? PFColors.onPrimary : PFColors.textSecondary,
                    )),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
