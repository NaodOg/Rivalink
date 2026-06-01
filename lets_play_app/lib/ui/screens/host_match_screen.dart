import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/playfair_theme.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_scaffold.dart';

class HostMatchScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const HostMatchScreen({super.key, required this.session, required this.repo});

  @override
  State<HostMatchScreen> createState() => _HostMatchScreenState();
}

class _HostMatchScreenState extends State<HostMatchScreen> {
  final _title = TextEditingController(text: '5v5 Football at Bole - 7 PM');
  final _description = TextEditingController(text: 'Looking for disciplined players. Bring white jersey.');
  final _location = TextEditingController(text: 'Bole Stadium');
  final _price = TextEditingController(text: '250');
  final _max = TextEditingController(text: '10');
  final _types = const ['5v5', '7v7', '11v11'];
  final _sports = const ['Football', 'Basketball', 'Tennis'];

  String _selectedSport = 'Football';
  String _selectedType = '5v5';
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 19, minute: 0);
  bool _isSubmitting = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _price.dispose();
    _max.dispose();
    super.dispose();
  }

  DateTime get _scheduledDateTime {
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _selectedTime);
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final token = widget.session.token;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }

    if (_title.text.trim().isEmpty || _location.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title and venue are required.')));
      return;
    }

    setState(() => _isSubmitting = true);
    final result = await widget.repo.createMatch(
      token: token,
      title: _title.text.trim(),
      sport: _selectedSport,
      description: '$_selectedType • ${_description.text.trim()}',
      location: _location.text.trim(),
      dateTime: _scheduledDateTime,
      maxPlayers: int.tryParse(_max.text) ?? 10,
      price: double.tryParse(_price.text) ?? 0,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((result['success'] == true ? 'Match created' : result['error']).toString())));
    if (result['success'] == true) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PFScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Host Match'),
      ),
      body: ListView(
        children: [
          PFCard(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 180,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        'assets/images/hero_soccer.jpg',
                        fit: BoxFit.cover,
                        alignment: Alignment.centerRight,
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              PFColors.background.withValues(alpha: 0.92),
                              PFColors.background.withValues(alpha: 0.62),
                              PFColors.background.withValues(alpha: 0.10),
                            ],
                            stops: const [0.0, 0.50, 1.0],
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 120, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('Host your next game', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.02)),
                          SizedBox(height: 8),
                          Text('Set details, lock your venue, and fill your squad quickly.', style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          PFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sport', style: TextStyle(color: PFColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _sports.map((sport) {
                    final active = _selectedSport == sport;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedSport = sport),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: active ? PFColors.accent : PFColors.cardSoft,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: active ? PFColors.accent : PFColors.border),
                        ),
                        child: Text(
                          sport,
                          style: TextStyle(
                            color: active ? PFColors.background : PFColors.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                const Text('Match Type', style: TextStyle(color: PFColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: _types.map((type) {
                    final active = _selectedType == type;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedType = type),
                          child: Container(
                            height: 38,
                            decoration: BoxDecoration(
                              color: active ? PFColors.accent : PFColors.cardSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Text(type, style: TextStyle(color: active ? PFColors.background : PFColors.text, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Match Title', style: TextStyle(color: PFColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                TextField(controller: _title, decoration: const InputDecoration(hintText: 'Match title')),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Notes', style: TextStyle(color: PFColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                TextField(controller: _description, minLines: 2, maxLines: 3, decoration: const InputDecoration(hintText: 'Add notes (skill, kit, rules...)')),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Venue', style: TextStyle(color: PFColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                TextField(controller: _location, decoration: const InputDecoration(hintText: 'Venue')),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Date & Time', style: TextStyle(color: PFColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(color: PFColors.cardSoft, borderRadius: BorderRadius.circular(14), border: Border.all(color: PFColors.border)),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(children: [const Icon(Icons.calendar_today_rounded, size: 18, color: PFColors.muted), const SizedBox(width: 8), Text('$_selectedDate'.split(' ').first, style: const TextStyle(fontWeight: FontWeight.w600))]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: _pickTime,
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(color: PFColors.cardSoft, borderRadius: BorderRadius.circular(14), border: Border.all(color: PFColors.border)),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(children: [const Icon(Icons.schedule_rounded, size: 18, color: PFColors.muted), const SizedBox(width: 8), Text(_selectedTime.format(context), style: const TextStyle(fontWeight: FontWeight.w600))]),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Fee per Player (Br)', style: TextStyle(color: PFColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                TextField(controller: _price, decoration: const InputDecoration(hintText: 'Fee per player'), keyboardType: TextInputType.number),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Maximum Players', style: TextStyle(color: PFColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                TextField(controller: _max, decoration: const InputDecoration(hintText: 'Max players'), keyboardType: TextInputType.number),
                const SizedBox(height: 16),
                PFButton(label: _isSubmitting ? 'Creating...' : 'Create Match', onTap: _isSubmitting ? () {} : _submit),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
