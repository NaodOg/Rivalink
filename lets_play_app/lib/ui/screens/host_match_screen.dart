import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
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
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _price.dispose();
    _max.dispose();
    super.dispose();
  }

  DateTime get _scheduled => DateTime(
      _date.year, _date.month, _date.day, _time.hour, _time.minute);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final token = widget.session.token;
    if (token == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please log in first.')));
      return;
    }
    if (_title.text.trim().isEmpty || _location.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Title and venue are required.')));
      return;
    }
    setState(() => _submitting = true);
    final result = await widget.repo.createMatch(
      token: token,
      title: _title.text.trim(),
      sport: _sport,
      description:
          '$_type${_description.text.trim().isEmpty ? '' : ' • ${_description.text.trim()}'}',
      location: _location.text.trim(),
      dateTime: _scheduled,
      maxPlayers: int.tryParse(_max.text) ?? 10,
      price: double.tryParse(_price.text) ?? 0,
      skillLevel: _skill,
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
                _field('Venue', TextField(
                  controller: _location,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'Pitch or area'),
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
          _label('Date & time'),
          const SizedBox(height: PFSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _PickerField(
                  icon: Icons.calendar_today_rounded,
                  text: '${_date.day}/${_date.month}/${_date.year}',
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: PFSpacing.md),
              Expanded(
                child: _PickerField(
                  icon: Icons.schedule_rounded,
                  text: _time.format(context),
                  onTap: _pickTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: PFSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _field('Fee / player (Br)', TextField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '0'),
                )),
              ),
              const SizedBox(width: PFSpacing.md),
              Expanded(
                child: _field('Max players', TextField(
                  controller: _max,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '10'),
                )),
              ),
            ],
          ),
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

class _PickerField extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  const _PickerField(
      {required this.icon, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: PFColors.surface,
          borderRadius: BorderRadius.circular(PFRadius.md),
          border: Border.all(color: PFColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: PFColors.textSecondary),
            const SizedBox(width: PFSpacing.sm),
            Text(text,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          ],
        ),
      ),
    );
  }
}
