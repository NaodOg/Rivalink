import 'package:intl/intl.dart';

String br(num value) => value == 0 ? 'Free' : 'Br ${value.toStringAsFixed(0)}';

String prettyDate(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(dt.year, dt.month, dt.day);
  if (target == today) return 'Today ${DateFormat('HH:mm').format(dt)}';
  if (target == today.add(const Duration(days: 1))) {
    return 'Tomorrow ${DateFormat('HH:mm').format(dt)}';
  }
  return DateFormat('dd MMM, HH:mm').format(dt);
}
