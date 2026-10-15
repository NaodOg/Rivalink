import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';

class SearchHeader extends StatefulWidget {
  final String hint;
  final ValueChanged<String>? onChanged;

  const SearchHeader({super.key, required this.hint, this.onChanged});

  @override
  State<SearchHeader> createState() => _SearchHeaderState();
}

class _SearchHeaderState extends State<SearchHeader> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    setState(() => _hasText = false);
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 14.5, color: PFColors.text),
      onChanged: (v) {
        final has = v.isNotEmpty;
        if (has != _hasText) setState(() => _hasText = has);
        widget.onChanged?.call(v);
      },
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search_rounded, color: PFColors.textTertiary),
        suffixIcon: _hasText
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: PFColors.textSecondary),
                onPressed: _clear,
              )
            : null,
      ),
    );
  }
}
