import 'package:flutter_test/flutter_test.dart';
import 'package:solitaire/core/game_registry.dart';
import 'package:solitaire/core/games/freecell.dart';
import 'package:solitaire/core/games/klondike.dart';

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

    test('lists exactly the three v1 variants', () {
      expect(GameRegistry.ids, <String>[
        'klondike-draw1',
        'klondike-draw3',
        'freecell',
      ]);
    });

    test('an unknown id is a programmer error (throws)', () {
      expect(() => GameRegistry.rulesFor('spider'), throwsArgumentError);
    });
  });
}
