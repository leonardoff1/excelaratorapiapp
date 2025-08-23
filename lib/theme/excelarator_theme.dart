// ExcelaratorAPI brand theme (v1)
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ExcelaratorColors {
  static const primary = Color(0xFF2F6DF6);
  static const secondary = Color(0xFF16B364);
  static const violet = Color(0xFF7A5AF8);
  static const amber = Color(0xFFFDB022);
  static const surfaceLight = Color(0xFFF8FAFC);
  static const surfaceDark = Color(0xFF0F172A);
  static const error = Color(0xFFD92D20);
  static const outlineLight = Color(0xFF94A3B8);
  static const outlineDark = Color(0xFF3E4C6D);
}

ThemeData excelaratorLight() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: ExcelaratorColors.primary,
      secondary: ExcelaratorColors.secondary,
      surface: ExcelaratorColors.surfaceLight,
      error: ExcelaratorColors.error,
      outline: ExcelaratorColors.outlineLight,
    ),
    textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
      headlineSmall: GoogleFonts.manrope(fontWeight: FontWeight.w700),
      titleMedium: GoogleFonts.manrope(fontWeight: FontWeight.w600),
      labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w600),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: ExcelaratorColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    cardTheme: CardTheme(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

ThemeData excelaratorDark() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: ExcelaratorColors.primary,
      secondary: ExcelaratorColors.secondary,
      surface: ExcelaratorColors.surfaceDark,
      error: ExcelaratorColors.error,
      outline: ExcelaratorColors.outlineDark,
    ),
    textTheme: GoogleFonts.interTextTheme(base.textTheme),
    cardTheme: CardTheme(
      color: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
