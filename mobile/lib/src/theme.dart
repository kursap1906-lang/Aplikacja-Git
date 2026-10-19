import 'package:flutter/material.dart';

abstract final class AppColors {
  static const canvas = Color(0xFF111419);
  static const panel = Color(0xFF191E25);
  static const panelRaised = Color(0xFF202630);
  static const stroke = Color(0xFF303843);
  static const blue = Color(0xFF74B5FF);
  static const mint = Color(0xFF75D9AC);
  static const amber = Color(0xFFFFBF70);
  static const coral = Color(0xFFFF8585);
  static const muted = Color(0xFFA3ADBA);
  static const foreground = Color(0xFFEBEEF3);
}

abstract final class AppTheme {
  static final dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.canvas,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.blue,
      onPrimary: Color(0xFF061625),
      secondary: AppColors.mint,
      surface: AppColors.panel,
      error: AppColors.coral,
      onSurface: AppColors.foreground,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.foreground,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.panel,
      hintStyle: const TextStyle(color: AppColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.stroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.blue),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.stroke),
      ),
    ),
    dividerColor: AppColors.stroke,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: AppColors.foreground),
      headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.foreground),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.foreground),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.foreground),
      bodyLarge: TextStyle(fontSize: 15, color: AppColors.foreground),
      bodyMedium: TextStyle(fontSize: 13, color: AppColors.foreground),
      bodySmall: TextStyle(fontSize: 12, color: AppColors.muted),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.panelRaised,
      contentTextStyle: const TextStyle(color: AppColors.foreground),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}