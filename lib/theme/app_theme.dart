import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,

    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff1565C0),
      brightness: Brightness.light,
    ),

    scaffoldBackgroundColor: const Color(0xffF5F7FA),

    cardColor: Colors.white,

    appBarTheme: const AppBarTheme(
      centerTitle: true,
      backgroundColor: Color(0xff1565C0),
      foregroundColor: Colors.white,
      elevation: 0,
    ),

    cardTheme: CardThemeData(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,

    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff2196F3),
      brightness: Brightness.dark,
    ),

    scaffoldBackgroundColor: const Color(0xff0F172A),

    cardColor: const Color(0xff1E293B),

    appBarTheme: const AppBarTheme(
      centerTitle: true,
      backgroundColor: Color(0xff111827),
      foregroundColor: Colors.white,
      elevation: 0,
    ),

    cardTheme: CardThemeData(
      color: Color(0xff1E293B),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    ),

    dividerColor: Colors.white24,
  );
}