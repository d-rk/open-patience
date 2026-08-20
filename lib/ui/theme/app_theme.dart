import 'package:flutter/material.dart';

import 'game_fonts.dart';
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
      // Quicksand is the app-wide default; the display styles used for large
      // headings switch to the characterful Lilita One face.
      fontFamily: GameFonts.body,
      textTheme: _textTheme,
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

  /// Body text stays on [GameFonts.body]; the display/headline/title tiers use
  /// [GameFonts.display] so large headings pick up the playful face.
  static const TextTheme _textTheme = TextTheme(
    displayLarge: TextStyle(fontFamily: GameFonts.display),
    displayMedium: TextStyle(fontFamily: GameFonts.display),
    displaySmall: TextStyle(fontFamily: GameFonts.display),
    headlineLarge: TextStyle(fontFamily: GameFonts.display),
    headlineMedium: TextStyle(fontFamily: GameFonts.display),
    headlineSmall: TextStyle(fontFamily: GameFonts.display),
    titleLarge: TextStyle(fontFamily: GameFonts.display),
  );
}
