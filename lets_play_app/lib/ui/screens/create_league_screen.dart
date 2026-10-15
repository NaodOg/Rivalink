import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';

class CreateLeagueScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const CreateLeagueScreen({super.key, required this.session, required this.repo});

  @override
  State<CreateLeagueScreen> createState() => _CreateLeagueScreenState();
}

class _CreateLeagueScreenState extends State<CreateLeagueScreen> {
  final _nameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _prizeCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String _sport = 'soccer';
  String _format = '5v5';
  int _maxTeams = 8;
  DateTime _startDate = DateTime.now().add(const Duration(days: 7));
  bool _saving = false;

  final _formats = ['3v3', '5v5', '7v7', '11v11', 'Doubles', 'Singles'];
  final _sports = [
    'soccer', 'basketball', 'tennis', 'volleyball', 'cricket', 'esports', 'other'
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _prizeCtrl.dispose();
    _feeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('League name is required')));
      return;
    }
    setState(() => _saving = true);
    final token = widget.session.token;
    if (token == null) {
      setState(() => _saving = false);
      return;
    }
    final result = await widget.repo.createLeague(
      token: token,
      name: name,
      sport: _sport,
      format: _format,
      maxTeams: _maxTeams,
      entryFee: double.tryParse(_feeCtrl.text) ?? 0,
      prize: _prizeCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
      startDate: _startDate,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result['success'] == true) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['error']?.toString() ?? 'Failed to create league')));
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
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
        title: const Text('Create a league'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text('Set up the competition',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text('Premium only — every team member needs Premium to compete.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: PFSpacing.xl),
          _label('League name'),
          const SizedBox(height: PFSpacing.sm),
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'e.g. Addis Premier League'),
          ),
          const SizedBox(height: PFSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Sport'),
                    const SizedBox(height: PFSpacing.sm),
                    _sportDropdown(),
                  ],
                ),
              ),
              const SizedBox(width: PFSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Format'),
                    const SizedBox(height: PFSpacing.sm),
                    _formatDropdown(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: PFSpacing.lg),
          PFCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MAX TEAMS', style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: 4),
                      Text('$_maxTeams',
                          style: PFType.number.copyWith(fontSize: 22)),
                    ],
                  ),
                ),
                _stepper(Icons.remove_rounded, () {
                  if (_maxTeams > 2) setState(() => _maxTeams--);
                }),
                const SizedBox(width: PFSpacing.md),
                _stepper(Icons.add_rounded, () {
                  if (_maxTeams < 64) setState(() => _maxTeams++);
                }),
              ],
            ),
          ),
          const SizedBox(height: PFSpacing.lg),
          _label('Details'),
          const SizedBox(height: PFSpacing.sm),
          PFCard(
            child: Column(
              children: [
                _field('Location', _locationCtrl, 'e.g. Addis Ababa Stadium'),
                const SizedBox(height: PFSpacing.md),
                Row(
                  children: [
                    Expanded(child: _field('Entry fee (Br)', _feeCtrl, '0 = free',
                        keyboard: TextInputType.number)),
                    const SizedBox(width: PFSpacing.md),
                    Expanded(child: _field('Prize', _prizeCtrl, 'Br 10,000 + Trophy')),
                  ],
                ),
                const SizedBox(height: PFSpacing.md),
                _field('Description', _descCtrl, 'What is this league about?', maxLines: 3),
              ],
            ),
          ),
          const SizedBox(height: PFSpacing.lg),
          _label('Start date'),
          const SizedBox(height: PFSpacing.sm),
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: PFColors.surface,
                borderRadius: BorderRadius.circular(PFRadius.md),
                border: Border.all(color: PFColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 17, color: PFColors.textSecondary),
                  const SizedBox(width: PFSpacing.sm),
                  Text('${_startDate.day}/${_startDate.month}/${_startDate.year}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  const Spacer(),
                  const Icon(Icons.edit_calendar_rounded,
                      size: 18, color: PFColors.textTertiary),
                ],
              ),
            ),
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
            child: PFButton(label: 'Create league', loading: _saving, onTap: _save),
          ),
        ),
      ),
    );
  }

  Widget _label(String t) =>
      Text(t.toUpperCase(), style: Theme.of(context).textTheme.labelSmall);

  Widget _field(String label, TextEditingController c, String hint,
      {int maxLines = 1, TextInputType keyboard = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          maxLines: maxLines,
          keyboardType: keyboard,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }

  Widget _sportDropdown() => DropdownButtonFormField<String>(
        value: _sport,
        isExpanded: true,
        dropdownColor: PFColors.surfaceRaised,
        items: _sports
            .map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(s[0].toUpperCase() + s.substring(1),
                      style: const TextStyle(fontSize: 14)),
                ))
            .toList(),
        onChanged: (v) {
          if (v != null) setState(() => _sport = v);
        },
        decoration: const InputDecoration(hintText: 'Sport'),
      );

  Widget _formatDropdown() => DropdownButtonFormField<String>(
        value: _format,
        isExpanded: true,
        dropdownColor: PFColors.surfaceRaised,
        items: _formats
            .map((f) => DropdownMenuItem(
                  value: f, child: Text(f, style: const TextStyle(fontSize: 14))))
            .toList(),
        onChanged: (v) {
          if (v != null) setState(() => _format = v);
        },
        decoration: const InputDecoration(hintText: 'Format'),
      );

  Widget _stepper(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: PFColors.surfaceHigh,
          borderRadius: BorderRadius.circular(PFRadius.md),
          border: Border.all(color: PFColors.border),
        ),
        child: Icon(icon, size: 20, color: PFColors.text),
      ),
    );
  }
}
