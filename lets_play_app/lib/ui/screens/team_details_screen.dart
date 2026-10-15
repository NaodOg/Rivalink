import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_avatar.dart';
import '../widgets/pf_badge.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_section_header.dart';

class TeamDetailsScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  final int teamId;
  final String teamName;
  const TeamDetailsScreen({
    super.key,
    required this.session,
    required this.repo,
    required this.teamId,
    required this.teamName,
  });

  @override
  State<TeamDetailsScreen> createState() => _TeamDetailsScreenState();
}

class _TeamDetailsScreenState extends State<TeamDetailsScreen> {
  List<dynamic> _members = [];
  List<dynamic> _requests = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final members = await widget.repo.getTeamMembers(token, widget.teamId);
      final requests = await widget.repo.getJoinRequests(token, widget.teamId);
      if (!mounted) return;
      setState(() {
        _members = List<dynamic>.from(members['members'] ?? []);
        _requests = List<dynamic>.from(requests['requests'] ?? []);
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

  void _openChat() {
    Navigator.pushNamed(context, AppRoutes.chat, arguments: {
      'teamId': widget.teamId,
      'title': '${widget.teamName} chat',
    });
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
        title: Text(widget.teamName),
        actions: [
          IconButton(
            onPressed: _openChat,
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            tooltip: 'Team chat',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PFColors.primary))
          : _error
              ? Center(
                  child: PFEmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: "Couldn't load team",
                    actionLabel: 'Retry',
                    onAction: _load,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    PFButton(
                      label: 'Open team chat',
                      variant: PFButtonVariant.secondary,
                      icon: Icons.forum_outlined,
                      onTap: _openChat,
                    ),
                    const SizedBox(height: PFSpacing.xxl),
                    PFSectionHeader(
                      eyebrow: 'Squad',
                      title: 'Roster',
                      trailing: PFBadge(label: '${_members.length}'),
                    ),
                    const SizedBox(height: PFSpacing.md),
                    if (_members.isEmpty)
                      const PFEmptyState(
                        icon: Icons.groups_outlined,
                        title: 'No members yet',
                      )
                    else
                      PFCard(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                        child: Column(
                          children: [
                            for (int i = 0; i < _members.length; i++) ...[
                              _memberRow(_members[i]),
                              if (i < _members.length - 1)
                                const Divider(height: 1, indent: 52, color: PFColors.hairline),
                            ],
                          ],
                        ),
                      ),
                    if (_requests.isNotEmpty) ...[
                      const SizedBox(height: PFSpacing.xxl),
                      PFSectionHeader(
                        eyebrow: 'Pending',
                        title: 'Join requests',
                        trailing: PFBadge(label: '${_requests.length}', color: PFColors.warning),
                      ),
                      const SizedBox(height: PFSpacing.md),
                      ..._requests.map((r) => Padding(
                            padding: const EdgeInsets.only(bottom: PFSpacing.sm),
                            child: PFCard(
                              child: Row(
                                children: [
                                  PFAvatar(name: r['user_name']?.toString(), size: 38),
                                  const SizedBox(width: PFSpacing.md),
                                  Expanded(
                                    child: Text(r['user_name']?.toString() ?? 'Request',
                                        style: Theme.of(context).textTheme.titleSmall),
                                  ),
                                  const PFBadge(label: 'PENDING', color: PFColors.warning),
                                ],
                              ),
                            ),
                          )),
                    ],
                  ],
                ),
    );
  }

  Widget _memberRow(dynamic m) {
    final name = (m['name'] ?? 'Member').toString();
    final role = (m['role'] ?? 'member').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          PFAvatar(name: name, size: 38),
          const SizedBox(width: PFSpacing.md),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall),
          ),
          if (role == 'owner' || role == 'admin')
            PFBadge(
                label: role.toUpperCase(),
                color: role == 'owner' ? PFColors.primary : PFColors.secondary),
        ],
      ),
    );
  }
}
