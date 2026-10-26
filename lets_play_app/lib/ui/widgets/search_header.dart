import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/data/services/analytics_service.dart';
import '../../core/theme/rivalink_theme.dart';

class SearchHeader extends StatefulWidget {
  final String hint;
  final ValueChanged<String>? onChanged;
  final String? analyticsScreen;

  const SearchHeader({
    super.key,
    required this.hint,
    this.onChanged,
    this.analyticsScreen,
  });

  @override
  State<SearchHeader> createState() => _SearchHeaderState();
}

class _SearchHeaderState extends State<SearchHeader> {
  final _controller = TextEditingController();
  bool _hasText = false;
  Timer? _analyticsDebounce;

  @override
  void dispose() {
    _analyticsDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _trackSearch(String value) {
    final q = value.trim();
    if (q.length < 2) return;
    _analyticsDebounce?.cancel();
    _analyticsDebounce = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      AnalyticsService.event('search_used', {
        'q': q.toLowerCase(),
        'screen': widget.analyticsScreen ?? '',
      });
    });
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
        _trackSearch(v);
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
