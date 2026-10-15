import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_scaffold.dart';

class NotificationsScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const NotificationsScreen({super.key, required this.session, required this.repo});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> _items = [];
  int _unread = 0;
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
    setState(() { _loading = true; _error = false; });
    try {
      final result = await widget.repo.getNotifications(token);
      if (!mounted) return;
      final items = List<dynamic>.from(result['notifications'] ?? []);
      final unread = (result['unread_count'] ?? 0) as int;
      setState(() {
        _items = items;
        _unread = unread;
        _loading = false;
      });
      if (unread > 0) {
        await widget.repo.markNotificationsRead(token);
      }
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
        title: const Text('Notifications'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PFColors.primary))
          : _error
              ? Center(
                  child: PFEmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: "Couldn't load notifications",
                    message: 'Check your connection and try again.',
                    actionLabel: 'Retry',
                    onAction: _load,
                  ),
                )
              : ListView(
              children: [
                ..._items.map((n) {
                  final type = n['type']?.toString() ?? '';
                  final isChat = type == 'chat_message';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: PFCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isChat ? PFColors.accent.withValues(alpha: 0.15) : PFColors.cardSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isChat ? Icons.chat_bubble_outline_rounded : Icons.notifications_outlined,
                              color: isChat ? PFColors.accent : PFColors.muted,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text((n['title'] ?? 'Notification').toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                const SizedBox(height: 4),
                                Text((n['message'] ?? '').toString(), style: const TextStyle(color: PFColors.muted, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          if (n['is_read'] != true)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              width: 8, height: 8,
                              decoration: const BoxDecoration(color: PFColors.primary, shape: BoxShape.circle),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
                if (_items.isEmpty)
                  const PFEmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'No notifications yet',
                    message: 'Match invites, results and chats show up here.',
                  ),
              ],
            ),
    );
  }
}
