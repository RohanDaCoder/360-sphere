import 'package:flutter/material.dart';

/// Design tokens for 360Sphere.
///
/// The palette echoes the original 360 Photo Cam app: a near-black camera UI
/// with a deep-orange accent (the original ships the accent color `#BF360C`).
abstract final class AppTheme {
  static const Color bg = Color(0xFF101214);
  static const Color surface = Color(0xFF1A1D20);
  static const Color surfaceHigh = Color(0xFF262A2E);
  static const Color accent = Color(0xFFE64A19);
  static const Color accentDeep = Color(0xFFBF360C);
  static const Color ok = Color(0xFF43A047);
  static const Color warn = Color(0xFFFFB300);

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accentDeep,
        surface: surface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Montserrat',
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: Colors.white,
        ),
      ),
      textTheme: base.textTheme.apply(
        fontFamily: 'Inter',
        displayColor: Colors.white,
        bodyColor: Colors.white,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        selectedColor: accent,
        labelStyle: const TextStyle(fontFamily: 'Montserrat', fontSize: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(
              fontFamily: 'Montserrat', fontWeight: FontWeight.w600),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        labelStyle: const TextStyle(fontFamily: 'Inter'),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: TextStyle(color: Colors.white, fontFamily: 'Inter'),
      ),
    );
  }
}
