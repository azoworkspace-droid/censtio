import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design system for the Freelancer app.
/// All colors, gradients, radii, and text styles live here.
abstract class AppTheme {
  // ── Palette ─────────────────────────────────────────────────────────────────

  /// Deep navy — scaffold / page background.
  static const Color bgDeep = Color(0xFF0B0F19);

  /// Slightly lighter navy — card surfaces.
  static const Color bgCard = Color(0xFF131929);

  /// Very dark surface used inside glass cards.
  static const Color bgSurface = Color(0xFF1A2236);

  /// Neon emerald — the primary accent colour.
  static const Color emerald = Color(0xFF00E5A0);

  /// Dimmer emerald for secondary/disabled states.
  static const Color emeraldDim = Color(0xFF00B37D);

  /// Soft emerald glow used in shadows / halos.
  static const Color emeraldGlow = Color(0x4000E5A0); // 25 % opacity

  /// Text — full white.
  static const Color textPrimary = Colors.white;

  /// Text — muted 60 % white.
  static const Color textSecondary = Color(0xB3FFFFFF);

  /// Text — very muted 35 % white.
  static const Color textHint = Color(0x80FFFFFF);

  /// Error / overdue red.
  static const Color errorRed = Color(0xFFFF5370);

  /// Warning / pending amber.
  static const Color warningAmber = Color(0xFFFFB74D);

  /// Warm secondary accent used for premium affordances and attention cues.
  static const Color orange = Color(0xFFFF9F43);

  /// Glass card border colour.
  static const Color glassBorder = Color(0x26FFFFFF); // 15 % white

  /// Electric blue / cyan accent used for Quotes/Devis.
  static const Color electricBlue = Color(0xFF38BDF8);

  // ── Gradients ───────────────────────────────────────────────────────────────

  static const LinearGradient emeraldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00E5A0), Color(0xFF00B37D)],
  );

  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0D1425), Color(0xFF0B0F19)],
  );

  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x1FFFFFFF), Color(0x0AFFFFFF)],
  );

  // ── Radii ───────────────────────────────────────────────────────────────────

  static const double radiusXL = 28.0;
  static const double radiusLG = 20.0;
  static const double radiusMD = 14.0;
  static const double radiusSM = 10.0;

  // ── Typography ──────────────────────────────────────────────────────────────

  static TextStyle displayLarge({Color color = Colors.white}) =>
      GoogleFonts.inter(
        fontSize: 42,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -1.5,
        height: 1.1,
      );

  static TextStyle headlineMedium({Color color = Colors.white}) =>
      GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.5,
      );

  static TextStyle titleLarge({Color color = Colors.white}) =>
      GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle bodyLarge({Color color = Colors.white}) => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: color,
  );

  static TextStyle bodyMedium({Color color = const Color(0x99FFFFFF)}) =>
      GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle labelSmall({Color color = const Color(0x59FFFFFF)}) =>
      GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.8,
      );

  // ── MaterialApp ThemeData ───────────────────────────────────────────────────

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDeep,
      colorScheme: ColorScheme.dark(
        primary: emerald,
        secondary: emeraldDim,
        surface: bgCard,
        error: errorRed,
        onPrimary: bgDeep,
        onSecondary: bgDeep,
        onSurface: textPrimary,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLG),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: titleLarge(),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0x1AFFFFFF),
        thickness: 1,
      ),
      iconTheme: const IconThemeData(color: textSecondary),
    );
  }
}
