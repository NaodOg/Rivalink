import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/playfair_theme.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_scaffold.dart';

class TeamDetailsScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  final int teamId;
  final String teamName;
  const TeamDetailsScreen({super.key, required this.session, required this.repo, required this.teamId, required this.teamName});

  @override
  State<TeamDetailsScreen> createState() => _TeamDetailsScreenState();
}

class _TeamDetailsScreenState extends State<TeamDetailsScreen> {
  List<dynamic> _members = [];
  List<dynamic> _requests = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    final members = await widget.repo.getTeamMembers(token, widget.teamId);
    final requests = await widget.repo.getJoinRequests(token, widget.teamId);
    if (!mounted) return;
    setState(() {
      _members = List<dynamic>.from(members['members'] ?? []);
      _requests = List<dynamic>.from(requests['requests'] ?? []);
    });
  }

  void _openChat() {
    Navigator.pushNamed(context, AppRoutes.chat, arguments: {
      'teamId': widget.teamId,
      'title': '${widget.teamName} Chat',
    });
  }

  @override
  Widget build(BuildContext context) {
    return PFScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.teamName),
        actions: [
          IconButton(
            onPressed: _openChat,
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            tooltip: 'Team Chat',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PFButton(
            label: 'Team Chat',
            onTap: _openChat,
          ),
          const SizedBox(height: 20),
          const Text('Roster', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ..._members.map((m) => PFCard(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [const CircleAvatar(radius: 12, backgroundColor: PFColors.cardSoft), const SizedBox(width: 8), Text((m['name'] ?? 'Member').toString())]),
          ))),
          if (_members.isEmpty) const Text('No members data yet', style: TextStyle(color: PFColors.muted)),
          const SizedBox(height: 14),
          const Text('Join Requests', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ..._requests.map((r) => PFCard(child: Text((r['user_name'] ?? 'Request').toString()))),
          if (_requests.isEmpty) const Text('No pending requests', style: TextStyle(color: PFColors.muted)),
        ],
      ),
    );
  }
}