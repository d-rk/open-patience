import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/game_registry.dart';
import 'package:open_patience/core/games/freecell.dart';
import 'package:open_patience/core/games/klondike.dart';

void main() {
  group('GameRegistry', () {
    test('maps every known id to the right rules with a matching id', () {
      expect(GameRegistry.rulesFor('klondike-draw1'), isA<KlondikeRules>());
      expect(
        (GameRegistry.rulesFor('klondike-draw1') as KlondikeRules).drawCount,
        1,
      );
      expect(
        (GameRegistry.rulesFor('klondike-draw3') as KlondikeRules).drawCount,
        3,
      );
      expect(GameRegistry.rulesFor('freecell'), isA<FreecellRules>());

      for (final String id in GameRegistry.ids) {
        expect(
          GameRegistry.rulesFor(id).id,
          id,
          reason: 'rules.id must match its registry id',
        );
      }
    });

    test('lists exactly the five variants in menu order', () {
      expect(GameRegistry.ids, <String>[
        'klondike-draw1',
        'klondike-draw3',
        'freecell',
        'freecell-cells2',
        'freecell-cells6',
      ]);
    });

    test('maps the FreeCell cell-count variants', () {
      expect(
        (GameRegistry.rulesFor('freecell-cells2') as FreecellRules)
            .freecellCount,
        2,
      );
      expect(
        (GameRegistry.rulesFor('freecell-cells6') as FreecellRules)
            .freecellCount,
        6,
      );
    });

    test('an unknown id is a programmer error (throws)', () {
      expect(() => GameRegistry.rulesFor('spider'), throwsArgumentError);
    });
  });
}
