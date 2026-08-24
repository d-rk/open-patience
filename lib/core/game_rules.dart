import 'card.dart';
import 'deck.dart';
import 'game_state.dart';
import 'move.dart';
import 'pile.dart';

/// The extensibility hinge of the engine. Everything variant-specific lives
/// behind this interface; [GameState] delegates to it and knows nothing about
/// which game is being played. A new solitaire variant is one new file that
/// implements [GameRules].
abstract class GameRules {
  /// Stable identifier used by the registry and the save/stats keys, e.g.
  /// `'klondike-draw1'`, `'freecell'`.
  String get id;

  /// The number of cards in the tallest tableau column of this variant's
  /// opening deal (Klondike 7, FreeCell 7). It is the reference the board uses
  /// to cap card size: as a game shortens toward a win the cards never grow
  /// larger than they were at the deal — the freed space becomes margin.
  int get openingMaxTableau;

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

  /// A system move that cycles the stock to expose new cards (a draw, or a
  /// recycle once the stock is exhausted), or `null` for variants with no
  /// stock or nothing left to cycle. Used by the auto-solver to reach buried
  /// cards. Apply with [GameState.applyMove].
  Move? advanceStock(GameState state);
}
