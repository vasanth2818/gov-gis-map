import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Montserrat',
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF005A9C), // A professional "government blue"
        primary: const Color(0xFF005A9C),
        secondary: const Color(0xFF00A9E0),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF005A9C),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF005A9C),
        foregroundColor: Colors.white,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Montserrat',
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF005A9C),
        brightness: Brightness.dark,
        primary: const Color(0xFF005A9C),
        secondary: const Color(0xFF00A9E0),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }
}
