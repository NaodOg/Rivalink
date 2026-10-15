import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';

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
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: PFSpacing.sm),
        itemBuilder: (_, i) {
          final label = labels[i];
          return Center(
            child: ChoiceChip(
              label: Text(label),
              selected: selected == label,
              onSelected: (_) => onSelected(label),
            ),
          );
        },
      ),
    );
  }
}
