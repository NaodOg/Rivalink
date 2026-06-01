import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/playfair_theme.dart';
import '../widgets/pf_scaffold.dart';

class ChatScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  final int matchId;
  final String title;
  const ChatScreen({super.key, required this.session, required this.repo, required this.matchId, required this.title});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  List<dynamic> _messages = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await widget.repo.getMatchChat(token, widget.matchId);
      if (!mounted) return;
      setState(() {
        _messages = data;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Failed to load messages'; });
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final token = widget.session.token;
    if (token == null) return;
    final res = await widget.repo.sendMatchChat(token, widget.matchId, text);
    _input.clear();
    if (!mounted) return;
    if (res['success'] == true) {
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['error']?.toString() ?? 'Failed to send message'),
      ));
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
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: PFColors.accent))
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off_rounded, size: 48, color: PFColors.muted),
                            const SizedBox(height: 12),
                            Text(_error!, style: const TextStyle(color: PFColors.muted)),
                            const SizedBox(height: 12),
                            TextButton(onPressed: _load, child: const Text('Retry', style: TextStyle(color: PFColors.accent))),
                          ],
                        ),
                      )
                    : _messages.isEmpty
                        ? const Center(child: Text('No messages yet. Start the conversation!', style: TextStyle(color: PFColors.muted)))
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) {
                              final m = _messages[i];
                              final mine = m.userId == (widget.session.user?['id'] ?? -1);
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                                child: Align(
                                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                                    decoration: BoxDecoration(
                                      color: mine ? PFColors.accent.withValues(alpha: 0.15) : PFColors.card,
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(16),
                                        topRight: const Radius.circular(16),
                                        bottomLeft: mine ? const Radius.circular(16) : Radius.zero,
                                        bottomRight: mine ? Radius.zero : const Radius.circular(16),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                      children: [
                                        Text(m.userName, style: const TextStyle(color: PFColors.accent, fontSize: 11, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 3),
                                        Text(m.message, style: const TextStyle(fontSize: 14)),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: PFColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    onSubmitted: (_) => _send(),
                    style: const TextStyle(color: PFColors.text, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Send a message...',
                      hintStyle: const TextStyle(color: PFColors.muted, fontSize: 14),
                      filled: true,
                      fillColor: PFColors.card,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _send,
                  style: IconButton.styleFrom(backgroundColor: PFColors.accent, foregroundColor: PFColors.background),
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
