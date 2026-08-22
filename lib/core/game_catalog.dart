import 'game_registry.dart';

/// A game and the ordered list of variant ids it offers. The grouping layer
/// above the flat variant ids: the menu shows games, each game a list of
/// variants. Labels live in the UI; this file holds structure only.
class Game {
  const Game({required this.id, required this.variantIds});

  final String id;
  final List<String> variantIds;
}

/// Maps each game to its variants (menu order) and back. Every variant id here
/// must resolve in [GameRegistry]; a drift guard test enforces the two agree.
class GameCatalog {
  const GameCatalog._();

  static const String klondike = 'klondike';
  static const String freecell = 'freecell';

  static const List<Game> games = <Game>[
    Game(
      id: klondike,
      variantIds: <String>[
        GameRegistry.klondikeDraw1,
        GameRegistry.klondikeDraw3,
      ],
    ),
    Game(
      id: freecell,
      variantIds: <String>[
        GameRegistry.freecell,
        GameRegistry.freecellCells2,
        GameRegistry.freecellCells6,
      ],
    ),
  ];

  /// The game that offers [variantId]. Throws [ArgumentError] for an unknown id.
  static Game gameForVariant(String variantId) {
    for (final Game game in games) {
      if (game.variantIds.contains(variantId)) {
        return game;
      }
    }
    throw ArgumentError.value(variantId, 'variantId', 'Unknown variant');
  }
}
