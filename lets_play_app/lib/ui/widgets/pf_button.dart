import 'package:flutter/material.dart';

import '../../core/theme/playfair_theme.dart';

class PFButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const PFButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: PFColors.accent,
          foregroundColor: PFColors.background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          elevation: 0,
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}
