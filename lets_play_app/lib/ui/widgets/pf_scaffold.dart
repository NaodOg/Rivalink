import 'package:flutter/material.dart';

import '../../core/theme/playfair_theme.dart';

class PFScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final EdgeInsetsGeometry? padding;

  const PFScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      backgroundColor: PFColors.background,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E130E), PFColors.background],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
            child: body,
          ),
        ),
      ),
    );
  }
}
