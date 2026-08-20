import 'game_rules.dart';
import 'games/freecell.dart';
import 'games/klondike.dart';

/// Maps a stable variant id to a fresh [GameRules] instance. Adding a variant
/// is a new `games/` file plus one case here — never a change to [GameState],
/// [Move] or any widget.
class GameRegistry {
  const GameRegistry._();

  static const String klondikeDraw1 = 'klondike-draw1';
  static const String klondikeDraw3 = 'klondike-draw3';
  static const String freecell = 'freecell';

  /// All known variant ids, in menu order.
  static const List<String> ids = <String>[
    klondikeDraw1,
    klondikeDraw3,
    freecell,
  ];

  /// A fresh rules instance for [id]. Throws [ArgumentError] for an unknown id
  /// — that is a programmer error, not expected runtime input.
  static GameRules rulesFor(String id) {
    switch (id) {
      case klondikeDraw1:
        return KlondikeRules(drawCount: 1);
      case klondikeDraw3:
        return KlondikeRules(drawCount: 3);
      case freecell:
        return FreecellRules();
      default:
        throw ArgumentError.value(id, 'id', 'Unknown variant');
    }
  }
}
