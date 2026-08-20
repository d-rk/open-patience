import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solitaire/ui/theme/app_theme.dart';
import 'package:solitaire/ui/theme/game_fonts.dart';
import 'package:solitaire/ui/theme/game_palette.dart';

void main() {
  test('themeData uses Material 3 and the gold secondary', () {
    final ThemeData theme = AppTheme.themeData;
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.secondary, GamePalette.gold);
  });

  test('themeData defaults body text to Quicksand, headings to Lilita One', () {
    final ThemeData theme = AppTheme.themeData;
    expect(theme.textTheme.bodyMedium?.fontFamily, GameFonts.body);
    expect(theme.textTheme.titleLarge?.fontFamily, GameFonts.display);
    expect(theme.textTheme.headlineMedium?.fontFamily, GameFonts.display);
  });
}
