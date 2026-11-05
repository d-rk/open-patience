import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/ui/theme/app_theme.dart';
import 'package:open_patience/ui/theme/game_fonts.dart';
import 'package:open_patience/ui/theme/game_palette.dart';

void main() {
  test('themeData uses Material 3 and the gold secondary', () {
    final ThemeData theme = AppTheme.themeData(const Locale('en'));
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.secondary, GamePalette.gold);
  });

  test('themeData defaults body text to Quicksand, headings to Lilita One', () {
    final ThemeData theme = AppTheme.themeData(const Locale('en'));
    expect(theme.textTheme.bodyMedium?.fontFamily, GameFonts.body);
    expect(theme.textTheme.titleLarge?.fontFamily, GameFonts.display);
    expect(theme.textTheme.headlineMedium?.fontFamily, GameFonts.display);
  });
  test('Russian headings use Roboto Condensed Bold', () {
    final ThemeData theme = AppTheme.themeData(const Locale('ru', 'RU'));
    expect(theme.textTheme.titleLarge?.fontFamily, 'sans-serif-condensed');
    expect(theme.textTheme.bodyMedium?.fontFamily, 'sans-serif-light');
    expect(theme.textTheme.titleLarge?.fontWeight, FontWeight.w700);
  });
}
