import 'package:flutter/material.dart';

import 'game_palette.dart';

/// The app-wide [ThemeData]. Wired into the root `MaterialApp` so standard
/// Material widgets inherit the Emerald Felt look with no per-widget styling.
class AppTheme {
  AppTheme._();

  static ThemeData get themeData {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: GamePalette.feltGreenLight,
      primary: GamePalette.feltGreenMid,
      secondary: GamePalette.gold,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: GamePalette.feltGreenDark,
      cardTheme: CardThemeData(
        color: GamePalette.cardFace,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: GamePalette.cardFace,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          backgroundColor: GamePalette.feltGreenMid,
          foregroundColor: GamePalette.cardFace,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          foregroundColor: GamePalette.feltGreenMid,
          side: const BorderSide(color: GamePalette.feltGreenMid, width: 2),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: GamePalette.feltGreenMid),
      ),
    );
  }
}
