import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/ui/variant_labels.dart';

void main() {
  test('variantTitle covers all five variants', () {
    expect(variantTitle('klondike-draw1'), 'Klondike (Draw 1)');
    expect(variantTitle('klondike-draw3'), 'Klondike (Draw 3)');
    expect(variantTitle('freecell'), 'FreeCell');
    expect(variantTitle('freecell-cells2'), 'FreeCell (2 cells)');
    expect(variantTitle('freecell-cells6'), 'FreeCell (6 cells)');
  });

  test('gameTitle names each game', () {
    expect(gameTitle('klondike'), 'Klondike');
    expect(gameTitle('freecell'), 'FreeCell');
  });

  test('variantShortLabel and descriptor are defined per variant', () {
    expect(variantShortLabel('klondike-draw1'), 'Draw 1');
    expect(variantShortLabel('freecell'), 'Classic · 4 cells');
    expect(variantShortLabel('freecell-cells2'), '2 cells · hard');
    expect(variantShortLabel('freecell-cells6'), '6 cells · relaxed');
    expect(variantDescriptor('freecell'), isNotEmpty);
  });
}
