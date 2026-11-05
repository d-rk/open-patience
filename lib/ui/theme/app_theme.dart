import 'package:flutter/material.dart';

import 'game_fonts.dart';
import 'game_palette.dart';

/// The app-wide [ThemeData]. Wired into the root `MaterialApp` so standard
/// Material widgets inherit the Emerald Felt look with no per-widget styling.
class AppTheme {
  AppTheme._();

  static ThemeData themeData(Locale locale) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: GamePalette.feltGreenLight,
      primary: GamePalette.feltGreenMid,
      secondary: GamePalette.gold,
    );
    final useSystemFonts = shouldUseSystemFonts(locale);
    final bodyFont = useSystemFonts ? GameFonts.system : GameFonts.body;
    final textTheme = useSystemFonts
        ? _textTheme(GameFonts.systemCondensed, fontWeight: FontWeight.w700)
        : _textTheme(GameFonts.display);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: GamePalette.feltGreenDark,
      // Quicksand is the app-wide default; the display styles used for large
      // headings switch to the characterful Lilita One face.
      fontFamily: bodyFont,
      textTheme: textTheme,
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

  static bool shouldUseSystemFonts(Locale locale) =>
      locale.languageCode == 'ru';

  /// Body text stays on [GameFonts.body]; the display/headline/title tiers use
  /// [GameFonts.display] so large headings pick up the playful face.
  static TextTheme _textTheme(String fontFamily, {FontWeight? fontWeight}) {
    final headingStyle = TextStyle(
      fontFamily: fontFamily,
      fontWeight: fontWeight,
    );
    return TextTheme(
      displayLarge: headingStyle,
      displayMedium: headingStyle,
      displaySmall: headingStyle,
      headlineLarge: headingStyle,
      headlineMedium: headingStyle,
      headlineSmall: headingStyle,
      titleLarge: headingStyle,
    );
  }
}
