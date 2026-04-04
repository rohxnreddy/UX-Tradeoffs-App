// lib/src/core/theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ── Palette ───────────────────────────────────────────────────────────────
  static const bg       = Color(0xFF0D0F14);   // deep navy-black
  static const surface  = Color(0xFF161A22);   // card surface
  static const surface2 = Color(0xFF1E2430);   // elevated card
  static const border   = Color(0xFF2A3040);
  static const accent   = Color(0xFF00C8FF);   // cyan-electric
  static const accentDim= Color(0xFF0097B8);
  static const good     = Color(0xFF00E676);
  static const warn     = Color(0xFFFFB300);
  static const bad      = Color(0xFFFF4444);
  static const textPri  = Color(0xFFF0F4FF);
  static const textSec  = Color(0xFF8A95A8);
  static const textDim  = Color(0xFF4A5568);

  // ── Test accent colours ───────────────────────────────────────────────────
  static const vmafColor  = Color(0xFF00C8FF);
  static const peaqColor  = Color(0xFF7C4DFF);
  static const pesqColor  = Color(0xFF00E676);
  static const iqaColor   = Color(0xFFFF9100);
  static const battColor  = Color(0xFFFF4081);

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      surface: surface,
      primary: accent,
      secondary: good,
      error: bad,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      elevation: 0,
      foregroundColor: textPri,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: border),
      ),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: textSec, fontSize: 14),
      bodyLarge:  TextStyle(color: textPri, fontSize: 16),
    ),
  );
}
