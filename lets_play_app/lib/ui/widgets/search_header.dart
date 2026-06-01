import 'package:flutter/material.dart';

import '../../core/theme/playfair_theme.dart';

class SearchHeader extends StatelessWidget {
  final String hint;
  final ValueChanged<String>? onChanged;

  const SearchHeader({super.key, required this.hint, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: PFColors.muted),
        prefixIcon: const Icon(Icons.search_rounded, color: PFColors.muted),
        filled: true,
        fillColor: PFColors.card,
      ),
    );
  }
}
