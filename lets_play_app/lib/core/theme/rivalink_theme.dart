import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'design_tokens.dart';

export 'design_tokens.dart';

class RivalinkTheme {
  RivalinkTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    final display = GoogleFonts.spaceGroteskTextTheme(base.textTheme);
    final body = GoogleFonts.manropeTextTheme(base.textTheme);

    final textTheme = TextTheme(
      displayLarge: display.displayLarge?.copyWith(
          fontSize: 40, fontWeight: FontWeight.w800, height: 0.98,
          letterSpacing: -1.4, color: PFColors.text),
      displayMedium: display.displayMedium?.copyWith(
          fontSize: 32, fontWeight: FontWeight.w800, height: 1.0,
          letterSpacing: -1.0, color: PFColors.text),
      displaySmall: display.displaySmall?.copyWith(
          fontSize: 27, fontWeight: FontWeight.w800, height: 1.02,
          letterSpacing: -0.6, color: PFColors.text),
      headlineMedium: display.headlineMedium?.copyWith(
          fontSize: 22, fontWeight: FontWeight.w800, height: 1.1,
          letterSpacing: -0.5, color: PFColors.text),
      headlineSmall: display.headlineSmall?.copyWith(
          fontSize: 19, fontWeight: FontWeight.w700, height: 1.15,
          letterSpacing: -0.3, color: PFColors.text),
      titleLarge: display.titleLarge?.copyWith(
          fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2,
          color: PFColors.text),
      titleMedium: body.titleMedium?.copyWith(
          fontSize: 15.5, fontWeight: FontWeight.w700, color: PFColors.text),
      titleSmall: body.titleSmall?.copyWith(
          fontSize: 13.5, fontWeight: FontWeight.w700, color: PFColors.text),
      bodyLarge: body.bodyLarge?.copyWith(
          fontSize: 15, fontWeight: FontWeight.w500, height: 1.45,
          color: PFColors.text),
      bodyMedium: body.bodyMedium?.copyWith(
          fontSize: 14, fontWeight: FontWeight.w500, height: 1.45,
          color: PFColors.textSecondary),
      bodySmall: body.bodySmall?.copyWith(
          fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.4,
          color: PFColors.textSecondary),
      labelLarge: body.labelLarge?.copyWith(
          fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: 0.2,
          color: PFColors.text),
      labelMedium: body.labelMedium?.copyWith(
          fontSize: 12, fontWeight: FontWeight.w600, color: PFColors.textSecondary),
      labelSmall: body.labelSmall?.copyWith(
          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.9,
          color: PFColors.textTertiary),
    );

    const scheme = ColorScheme.dark(
      surface: PFColors.background,
      surfaceContainerHighest: PFColors.surfaceHigh,
      primary: PFColors.primary,
      onPrimary: PFColors.onPrimary,
      secondary: PFColors.secondary,
      onSecondary: PFColors.onSecondary,
      error: PFColors.danger,
      onError: PFColors.onPrimary,
      onSurface: PFColors.text,
      outline: PFColors.border,
      outlineVariant: PFColors.hairline,
    );

    return base.copyWith(
      scaffoldBackgroundColor: PFColors.background,
      colorScheme: scheme,
      textTheme: textTheme,
      iconTheme: const IconThemeData(color: PFColors.textSecondary, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: PFColors.text,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PFColors.surface,
        hintStyle: const TextStyle(color: PFColors.textTertiary, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: _inputBorder(PFColors.border),
        enabledBorder: _inputBorder(PFColors.border),
        focusedBorder: _inputBorder(PFColors.primary, width: 1.5),
        errorBorder: _inputBorder(PFColors.danger),
        focusedErrorBorder: _inputBorder(PFColors.danger, width: 1.5),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: PFColors.surfaceRaised,
        selectedColor: PFColors.primary,
        side: const BorderSide(color: PFColors.border),
        labelStyle: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: PFColors.text),
        secondaryLabelStyle: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: PFColors.onPrimary),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PFRadius.pill)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        showCheckmark: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: PFColors.primary,
          foregroundColor: PFColors.onPrimary,
          disabledBackgroundColor: PFColors.surfaceHigh,
          disabledForegroundColor: PFColors.textTertiary,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PFRadius.pill)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: PFColors.text,
          side: const BorderSide(color: PFColors.border),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PFRadius.pill)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: PFColors.primary,
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
      ),
      dividerTheme: const DividerThemeData(
          color: PFColors.hairline, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: PFColors.surfaceHigh,
        contentTextStyle: const TextStyle(color: PFColors.text, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PFRadius.md)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: PFColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(PFRadius.xl))),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: PFColors.primary),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(PFRadius.md),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
