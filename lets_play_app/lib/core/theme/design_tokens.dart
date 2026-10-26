import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Rivalink design system — "Blue"
/// Neutral near-black surfaces, one confident accent, sport-coded category
/// colors, and a two-family type system (Space Grotesk / Manrope).
/// ─────────────────────────────────────────────────────────────────────────

class PFColors {
  PFColors._();

  /// Legacy accent switch (kept only for the volleyball category tint).
  static const bool useCyan = bool.fromEnvironment('CYAN', defaultValue: true);

  // Surfaces — neutral near-black, four perceptible steps.
  static const background = Color(0xFF0A0A0B);
  static const surface = Color(0xFF141417);
  static const surfaceRaised = Color(0xFF1B1B1F);
  static const surfaceHigh = Color(0xFF232328);
  static const border = Color(0xFF2C2C31);
  static const hairline = Color(0xFF1F1F23);

  // Brand accent — Rivalink blue.
  static const primary = Color(0xFF2B5BFF);
  static const primaryPressed = Color(0xFF1E45CC);
  static const onPrimary = Color(0xFFFFFFFF);

  // Signals.
  static const secondary = Color(0xFF5AA9FF);
  static const onSecondary = Color(0xFF06131F);
  static const danger = Color(0xFFFF5C57);
  static const warning = Color(0xFFFFB020);
  static const success = Color(0xFF57D98A);

  // Rank / medal tiers (Elo).
  static const bronze = Color(0xFFCD7F45);
  static const silver = Color(0xFFB6BDC6);
  static const gold = Color(0xFFF5C24B);
  static const platinum = Color(0xFF8FE3D6);

  // Text ramp.
  static const text = Color(0xFFF2F5EF);
  static const textSecondary = Color(0xFFA6AEA6);
  static const textTertiary = Color(0xFF6D766D);

  // Scrim for type over photography.
  static const scrim = Color(0xFF0A0A0B);

  // ── Legacy aliases ──
  static const card = surface;
  static const cardSoft = surfaceRaised;
  static const accent = primary;
  static const muted = textSecondary;
  static const scrimTop = Color(0xFF0D0D0F);
}

/// Per-sport identity colors — differentiation without stock photography.
class PFSport {
  PFSport._();

  static Color color(String sport) {
    final s = sport.toLowerCase();
    if (s.contains('soccer') || s.contains('foot')) return PFColors.primary;
    if (s.contains('basket')) return const Color(0xFFFF8A3D);
    if (s.contains('tennis')) return const Color(0xFFF5D547);
    if (s.contains('volley')) {
      return PFColors.useCyan ? const Color(0xFF6E7BFF) : const Color(0xFF5AA9FF);
    }
    if (s.contains('cricket')) return const Color(0xFF57D98A);
    if (s.contains('esport') || s.contains('gaming')) return const Color(0xFFA78BFA);
    return PFColors.textSecondary;
  }

  static IconData icon(String sport) {
    final s = sport.toLowerCase();
    if (s.contains('soccer') || s.contains('foot')) {
      return PhosphorIcons.soccerBall(PhosphorIconsStyle.fill);
    }
    if (s.contains('basket')) return PhosphorIcons.basketball(PhosphorIconsStyle.fill);
    if (s.contains('tennis')) return PhosphorIcons.tennisBall(PhosphorIconsStyle.fill);
    if (s.contains('volley')) return PhosphorIcons.volleyball(PhosphorIconsStyle.fill);
    if (s.contains('cricket')) return PhosphorIcons.cricket(PhosphorIconsStyle.fill);
    if (s.contains('esport') || s.contains('gaming')) {
      return PhosphorIcons.gameController(PhosphorIconsStyle.fill);
    }
    return PhosphorIcons.trophy(PhosphorIconsStyle.fill);
  }
}

/// Phosphor icons for non-sport categories (matches the sport-icon set).
class PFIcons {
  PFIcons._();

  static IconData get venue => PhosphorIcons.buildings(PhosphorIconsStyle.fill);
  static IconData get referee => PhosphorIcons.sealCheck(PhosphorIconsStyle.fill);
  static IconData get booking => PhosphorIcons.calendarCheck(PhosphorIconsStyle.fill);
  static IconData get add => PhosphorIcons.plus(PhosphorIconsStyle.fill);
  static IconData get location => PhosphorIcons.mapPin(PhosphorIconsStyle.fill);
  static IconData get user => PhosphorIcons.user(PhosphorIconsStyle.fill);
  static IconData get users => PhosphorIcons.users(PhosphorIconsStyle.fill);
  static IconData get verified => PhosphorIcons.sealCheck(PhosphorIconsStyle.fill);
  static IconData get follow => PhosphorIcons.userPlus(PhosphorIconsStyle.fill);
  static IconData get edit => PhosphorIcons.pencilSimple(PhosphorIconsStyle.fill);
  static IconData get bell => PhosphorIcons.bell(PhosphorIconsStyle.fill);
  static IconData get gear => PhosphorIcons.gear(PhosphorIconsStyle.fill);
  static IconData get card => PhosphorIcons.creditCard(PhosphorIconsStyle.fill);
  static IconData get signOut => PhosphorIcons.signOut(PhosphorIconsStyle.fill);
  static IconData get crown => PhosphorIcons.crown(PhosphorIconsStyle.fill);
  static IconData get medal => PhosphorIcons.medal(PhosphorIconsStyle.fill);
  static IconData get trophy => PhosphorIcons.trophy(PhosphorIconsStyle.fill);
  static IconData get chevron => PhosphorIcons.caretRight(PhosphorIconsStyle.fill);
  static IconData get matches => PhosphorIcons.soccerBall(PhosphorIconsStyle.fill);
  static IconData get teams => PhosphorIcons.usersThree(PhosphorIconsStyle.fill);
}

/// Elo → rank tier (label + medal colour).
({String label, Color color}) pfEloTier(int elo) {
  if (elo >= 1600) return (label: 'Platinum', color: PFColors.platinum);
  if (elo >= 1400) return (label: 'Gold', color: PFColors.gold);
  if (elo >= 1200) return (label: 'Silver', color: PFColors.silver);
  return (label: 'Bronze', color: PFColors.bronze);
}

/// Progress toward the next tier: 0..1 fraction, points remaining, next label.
({double fraction, int remaining, String nextLabel}) pfEloProgress(int elo) {
  if (elo >= 1600) return (fraction: 1.0, remaining: 0, nextLabel: 'Top tier');
  if (elo >= 1400) {
    return (fraction: (elo - 1400) / 200, remaining: 1600 - elo, nextLabel: 'Platinum');
  }
  if (elo >= 1200) {
    return (fraction: (elo - 1200) / 200, remaining: 1400 - elo, nextLabel: 'Gold');
  }
  return (fraction: (elo / 1200).clamp(0.0, 1.0), remaining: 1200 - elo, nextLabel: 'Silver');
}

/// 4pt spacing scale.
class PFSpacing {
  PFSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

/// Corner-radius scale.
class PFRadius {
  PFRadius._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double xxl = 30;
  static const double pill = 999;
}

/// Type + motion tokens.
class PFType {
  PFType._();

  static const String display = 'SpaceGrotesk';
  static const String body = 'Manrope';
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static TextStyle get number => GoogleFonts.spaceGrotesk(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        fontFeatures: tabular,
      );
}

class PFMotion {
  PFMotion._();
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 420);
  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve standard = Curves.easeInOutCubic;
}
