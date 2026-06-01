import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PFColors {
  static const background = Color(0xFF0B0F0B);
  static const card = Color(0xFF161B16);
  static const cardSoft = Color(0xFF1B211B);
  static const border = Color(0xFF283128);
  static const accent = Color(0xFFC7E96A);
  static const accentDark = Color(0xFFA8CC44);
  static const text = Colors.white;
  static const muted = Color(0xFF9AA69A);
}

class PlayFairTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: PFColors.background,
      colorScheme: const ColorScheme.dark(
        surface: PFColors.background,
        primary: PFColors.accent,
        onPrimary: Color(0xFF0B0F0B),
        onSurface: PFColors.text,
      ),
      textTheme: GoogleFonts.lexendTextTheme(base.textTheme).apply(
        bodyColor: PFColors.text,
        displayColor: PFColors.text,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: PFColors.text,
        centerTitle: true,
        titleTextStyle: GoogleFonts.lexend(
          color: PFColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PFColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: PFColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: PFColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: PFColors.accent),
        ),
      ),
    );
  }
}
