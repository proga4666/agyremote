import 'package:flutter/material.dart';

class AntigravityTheme {
  static const Color background = Color(0xFF131314);
  static const Color surface = Color(0xFF1E1F20);
  static const Color surfaceContainer = Color(0xFF28292A);
  static const Color surfaceContainerHigh = Color(0xFF333538);
  static const Color border = Color(0xFF3C4043);
  static const Color borderSubtle = Color(0xFF2D3135);
  
  static const Color googleBlue = Color(0xFF8AB4F8);
  static const Color googleGreen = Color(0xFF81C995);
  static const Color googleAmber = Color(0xFFFDD663);
  static const Color googleRed = Color(0xFFF28B82);
  static const Color googlePurple = Color(0xFFC58AF9);

  static const Color textPrimary = Color(0xFFE3E3E3);
  static const Color textSecondary = Color(0xFF9AA0A6);
  static const Color textMuted = Color(0xFF6E7377);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: googleBlue,
      cardColor: surface,
      dividerColor: border,
      colorScheme: const ColorScheme.dark(
        surface: surface,
        primary: googleBlue,
        secondary: googleGreen,
        tertiary: googleAmber,
        error: googleRed,
        outline: border,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: border),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainer,
        labelStyle: const TextStyle(color: googleBlue),
        hintStyle: const TextStyle(color: textSecondary, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: googleBlue, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          side: const BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
      ),
    );
  }
}
