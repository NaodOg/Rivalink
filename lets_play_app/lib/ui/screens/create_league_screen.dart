import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/playfair_theme.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_scaffold.dart';

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
  final _sports = ['soccer', 'basketball', 'tennis', 'volleyball', 'cricket', 'esports', 'other'];

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('League name is required')));
      return;
    }

    setState(() => _saving = true);
    final token = widget.session.token;
    if (token == null) return;

    final fee = double.tryParse(_feeCtrl.text) ?? 0;

    final result = await widget.repo.createLeague(
      token: token,
      name: name,
      sport: _sport,
      format: _format,
      maxTeams: _maxTeams,
      entryFee: fee,
      prize: _prizeCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
      startDate: _startDate,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('League created!')));
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['error']?.toString() ?? 'Failed to create league')));
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
    return PFScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Create League'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('League Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PFColors.muted)),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(hintText: 'e.g. Addis Premier League'),
                ),
                const SizedBox(height: 16),
                const Text('Sport', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PFColors.muted)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _sport,
                  dropdownColor: PFColors.card,
                  items: _sports.map((s) => DropdownMenuItem(value: s, child: Text(s[0].toUpperCase() + s.substring(1), style: const TextStyle(fontSize: 14)))).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _sport = v);
                  },
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: PFColors.card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Format', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PFColors.muted)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _format,
                  dropdownColor: PFColors.card,
                  items: _formats.map((f) => DropdownMenuItem(value: f, child: Text(f, style: const TextStyle(fontSize: 14)))).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _format = v);
                  },
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: PFColors.card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Max Teams', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PFColors.muted)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _teamCountBtn(Icons.remove_rounded, () {
                      if (_maxTeams > 2) setState(() => _maxTeams--);
                    }),
                    const SizedBox(width: 16),
                    Text('$_maxTeams', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 16),
                    _teamCountBtn(Icons.add_rounded, () {
                      if (_maxTeams < 64) setState(() => _maxTeams++);
                    }),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Location', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PFColors.muted)),
                const SizedBox(height: 6),
                TextField(
                  controller: _locationCtrl,
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(hintText: 'e.g. Addis Ababa Stadium'),
                ),
                const SizedBox(height: 16),
                const Text('Entry Fee (Br)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PFColors.muted)),
                const SizedBox(height: 6),
                TextField(
                  controller: _feeCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(hintText: '0 = Free'),
                ),
                const SizedBox(height: 16),
                const Text('Prize', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PFColors.muted)),
                const SizedBox(height: 6),
                TextField(
                  controller: _prizeCtrl,
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(hintText: 'e.g. Br 10,000 + Trophy'),
                ),
                const SizedBox(height: 16),
                const Text('Description', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PFColors.muted)),
                const SizedBox(height: 6),
                TextField(
                  controller: _descCtrl,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(hintText: 'Tell teams what this league is about'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Start Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PFColors.muted)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: PFColors.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 16, color: PFColors.accent),
                        const SizedBox(width: 10),
                        Text(
                          '${_startDate.day}/${_startDate.month}/${_startDate.year}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        const Icon(Icons.edit_calendar_rounded, size: 18, color: PFColors.muted),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          PFButton(
            label: _saving ? 'Creating...' : 'Create League',
            onTap: _saving ? () {} : _save,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _teamCountBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: PFColors.cardSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: PFColors.text),
      ),
    );
  }
}
