import 'package:flutter/material.dart';

import '../../core/theme/playfair_theme.dart';

class FilterChipsRow extends StatelessWidget {
  final List<String> labels;
  final String selected;
  final ValueChanged<String> onSelected;

  const FilterChipsRow({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final label = labels[i];
          final active = selected == label;
          return GestureDetector(
            onTap: () => onSelected(label),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? PFColors.accent : PFColors.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: active ? PFColors.accent : PFColors.border),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: active ? PFColors.background : PFColors.text,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
