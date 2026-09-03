import 'package:flutter/material.dart';

class AppTheme {
  static const _bg = Color(0xFF111111);
  static const _surface = Color(0xFF1A1A1A);
  static const _surfaceHover = Color(0xFF252525);
  static const _border = Color(0xFF2A2A2A);
  static const _borderFocus = Color(0xFF555555);
  static const _text = Color(0xFFF5F5F5);
  static const _textMuted = Color(0xFF777777);

  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _bg,
    colorScheme: const ColorScheme.dark(
      surface: _bg,
      primary: _text,
      secondary: _textMuted,
      outline: _border,
    ),
    cardTheme: CardThemeData(
      color: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _border),
      ),
      elevation: 0,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 28),
      headlineMedium: TextStyle(color: _text, fontWeight: FontWeight.w600, fontSize: 20),
      bodyLarge: TextStyle(color: _text, fontWeight: FontWeight.w500, fontSize: 16),
      bodyMedium: TextStyle(color: _text, fontWeight: FontWeight.w400, fontSize: 14),
      bodySmall: TextStyle(color: _textMuted, fontWeight: FontWeight.w400, fontSize: 12),
      labelSmall: TextStyle(color: _textMuted, fontWeight: FontWeight.w500, fontSize: 11),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: _surface,
      selectedColor: _text,
      labelStyle: const TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w500),
      secondaryLabelStyle: const TextStyle(color: _bg, fontSize: 13, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: _border),
      ),
      side: const BorderSide(color: _border),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),
    iconTheme: const IconThemeData(color: _text, size: 20),
    dividerColor: _border,
  );

  /// TV panels overscan the edges. Android TV's guidance is 48 x 27 at 1080p,
  /// but real sets crop more than the guidance assumes, and a first test on a
  /// Google TV still clipped at those values. These sit a little inside.
  static const safeHorizontal = 64.0;
  static const safeVertical = 36.0;

  static const surface = _surface;
  static const surfaceHover = _surfaceHover;
  static const border = _border;
  static const borderFocus = _borderFocus;
  static const textPrimary = _text;
  static const textMuted = _textMuted;
}
