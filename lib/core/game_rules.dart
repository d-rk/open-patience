import 'card.dart';
import 'deck.dart';
import 'game_state.dart';
import 'pile.dart';

/// The extensibility hinge of the engine. Everything variant-specific lives
/// behind this interface; [GameState] delegates to it and knows nothing about
/// which game is being played. A new solitaire variant is one new file that
/// implements [GameRules].
abstract class GameRules {
  /// Stable identifier used by the registry and the save/stats keys, e.g.
  /// `'klondike-draw1'`, `'freecell'`.
  String get id;

  /// Deals [deck] (already shuffled by the caller with a seeded [Random]) into
  /// the pile layout for this variant. The returned list order is the canonical
  /// pile index order used everywhere else (moves, [autoTargets], serialized
  /// state).
  List<Pile> deal(Deck deck);

  /// A fixed, non-random layout for this variant with all four foundations
  /// built up to Queen and the four Kings face up and reachable — one move
  /// per King away from a win. Exists purely to exercise the win/records
  /// pipeline quickly during testing; never used by a real deal.
  List<Pile> dealAlmostWon();

  /// Whether moving [cards] (a contiguous top group of [fromPile], bottom-most
  /// of the group first) onto [toPile] is legal in the current [state].
  bool isLegalMove(GameState state, int fromPile, List<Card> cards, int toPile);

  /// Whether [state] is a completed win for this variant.
  bool isWon(GameState state);

  /// Legal destination pile indices for auto-move interactions (tap-to-move
  /// and double-tap-to-foundation). Moves the group starting at [cardIndex]
  /// within [fromPile] (defaults to the top card). The caller filters the
  /// result — e.g. keep only foundation piles for double-tap.
  List<int> autoTargets(GameState state, int fromPile, {int? cardIndex});

  /// The maximum number of cards that may be moved as a single group given the
  /// current free capacity (free cells / empty columns). [toPile], when given,
  /// excludes an empty destination column from the capacity math.
  int maxMovable(GameState state, {int? toPile});
}
