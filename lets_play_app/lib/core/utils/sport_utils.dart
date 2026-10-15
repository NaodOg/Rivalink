import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

IconData sportIcon(String sport) => PFSport.icon(sport);

List<Color> sportGradient(String sport) {
  final s = sport.toLowerCase();
  if (s.contains('soccer') || s.contains('football')) return const [Color(0xFF1A3A1A), Color(0xFF0D1F0D)];
  if (s.contains('basketball')) return const [Color(0xFF3A1A1A), Color(0xFF1F0D0D)];
  if (s.contains('tennis')) return const [Color(0xFF2A3A1A), Color(0xFF141F0D)];
  return const [Color(0xFF1A2A3A), Color(0xFF0D141F)];
}
