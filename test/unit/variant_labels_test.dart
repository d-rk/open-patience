import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/l10n/app_localizations_en.dart';
import 'package:open_patience/ui/variant_labels.dart';

void main() {
  test('variantTitle covers all five variants', () {
    final localizations = AppLocalizationsEn();
    expect(variantTitle(localizations, 'klondike-draw1'), 'Klondike (Draw 1)');
    expect(variantTitle(localizations, 'klondike-draw3'), 'Klondike (Draw 3)');
    expect(variantTitle(localizations, 'freecell'), 'FreeCell');
    expect(
      variantTitle(localizations, 'freecell-cells2'),
      'FreeCell (2 cells)',
    );
    expect(
      variantTitle(localizations, 'freecell-cells6'),
      'FreeCell (6 cells)',
    );
  });

  test('gameTitle names each game', () {
    final localizations = AppLocalizationsEn();
    expect(gameTitle(localizations, 'klondike'), 'Klondike');
    expect(gameTitle(localizations, 'freecell'), 'FreeCell');
  });

  test('variantShortLabel and descriptor are defined per variant', () {
    final localizations = AppLocalizationsEn();
    expect(variantShortLabel(localizations, 'klondike-draw1'), 'Draw 1');
    expect(variantShortLabel(localizations, 'freecell'), 'Classic · 4 cells');
    expect(
      variantShortLabel(localizations, 'freecell-cells2'),
      '2 cells · hard',
    );
    expect(
      variantShortLabel(localizations, 'freecell-cells6'),
      '6 cells · relaxed',
    );
    expect(variantDescriptor(localizations, 'freecell'), isNotEmpty);
  });
}
