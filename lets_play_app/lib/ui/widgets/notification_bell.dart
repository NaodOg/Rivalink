import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';

class NotificationBell extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;

  const NotificationBell({super.key, required this.session, required this.repo});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unreadCount = 0;
  Timer? _timer;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    final token = widget.session.token;
    if (token == null) return;
    final result = await widget.repo.getNotifications(token);
    if (!mounted) return;
    setState(() {
      _unreadCount = (result['unread_count'] ?? 0) as int;
      _initialized = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_outlined, color: PFColors.text, size: 24),
          onPressed: () {
            Navigator.pushNamed(context, '/notifications').then((_) => _fetch());
          },
        ),
        if (_initialized && _unreadCount > 0)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: PFColors.danger,
                borderRadius: BorderRadius.circular(PFRadius.pill),
                border: Border.all(color: PFColors.background, width: 1.5),
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 16),
              alignment: Alignment.center,
              child: Text(
                _unreadCount > 99 ? '99+' : '$_unreadCount',
                style: const TextStyle(
                  color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
