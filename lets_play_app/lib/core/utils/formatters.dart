String br(num value) => value == 0 ? 'Free' : 'Br ${value.toStringAsFixed(0)}';

String _formatTime(DateTime dt) {
  final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  return '$hour:${dt.minute.toString().padLeft(2, '0')} $period';
}

String prettyDate(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final dayDiff = day.difference(today).inDays;
  if (dayDiff <= 0) return 'Today, ${_formatTime(dt)}';
  if (dayDiff == 1) return 'Tomorrow, ${_formatTime(dt)}';
  if (dayDiff < 7) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[dt.weekday - 1]}, ${_formatTime(dt)}';
  }
  return '${dt.day}/${dt.month}, ${_formatTime(dt)}';
}

String shortDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';
