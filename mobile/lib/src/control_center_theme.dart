import 'package:flutter/material.dart';

ThemeData controlCenterTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xff0c1424),
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xff9c87f5),
    brightness: Brightness.dark,
  ),
  cardTheme: CardThemeData(
    color: const Color(0xff172338),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xff29384e)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
  ),
);
