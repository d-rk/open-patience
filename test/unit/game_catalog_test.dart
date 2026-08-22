import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/game_catalog.dart';
import 'package:open_patience/core/game_registry.dart';

void main() {
  group('GameCatalog', () {
    test('groups variants under two games in menu order', () {
      expect(GameCatalog.games.map((Game g) => g.id).toList(), <String>[
        'klondike',
        'freecell',
      ]);
      final Game klondike = GameCatalog.games.firstWhere(
        (Game g) => g.id == 'klondike',
      );
      expect(klondike.variantIds, <String>['klondike-draw1', 'klondike-draw3']);
      final Game freecell = GameCatalog.games.firstWhere(
        (Game g) => g.id == 'freecell',
      );
      expect(freecell.variantIds, <String>[
        'freecell',
        'freecell-cells2',
        'freecell-cells6',
      ]);
    });

    test('gameForVariant returns the owning game', () {
      expect(GameCatalog.gameForVariant('klondike-draw3').id, 'klondike');
      expect(GameCatalog.gameForVariant('freecell-cells2').id, 'freecell');
    });

    test('gameForVariant throws for an unknown variant', () {
      expect(() => GameCatalog.gameForVariant('spider'), throwsArgumentError);
    });

    test('catalog and registry cover exactly the same variant ids', () {
      final Set<String> catalogIds = <String>{
        for (final Game g in GameCatalog.games) ...g.variantIds,
      };
      expect(catalogIds, GameRegistry.ids.toSet());
      for (final String id in catalogIds) {
        expect(GameRegistry.rulesFor(id).id, id);
      }
    });
  });
}
