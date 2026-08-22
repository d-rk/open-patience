import '../card.dart';
import '../deck.dart';
import '../game_rules.dart';
import '../game_state.dart';
import '../pile.dart';
import 'sequence.dart';

/// FreeCell solitaire.
///
/// Pile layout (canonical index order):
/// * `0`..`3`   — four free cells (hold one card each)
/// * `4`..`7`   — foundations (one per suit, built up Ace..King)
/// * `8`..`15`  — eight tableau columns (all cards dealt face up)
///
/// The signature move constraint is [maxMovable]: with no real "pick up a
/// stack" mechanic, moving N cards as a group is only shorthand for a chain of
/// single-card moves through the free cells and empty columns, so the group
/// size is capped by `(freeCells + 1) * 2^(emptyColumns)`.
class FreecellRules implements GameRules {
  FreecellRules({this.freecellCount = 4})
    : assert(
        freecellCount >= 1 && freecellCount <= 8,
        'freecellCount must be between 1 and 8',
      );

  static const int firstFreecell = 0;
  static const int foundationCount = 4;
  static const int tableauCount = 8;

  final int freecellCount;

  int get firstFoundation => freecellCount;
  int get firstTableau => freecellCount + foundationCount;

  @override
  String get id =>
      freecellCount == 4 ? 'freecell' : 'freecell-cells$freecellCount';

  @override
  List<Pile> deal(Deck deck) {
    final List<Pile> piles = <Pile>[
      for (int i = 0; i < freecellCount; i++) Pile(kind: PileKind.freecell),
      for (int i = 0; i < foundationCount; i++) Pile(kind: PileKind.foundation),
      for (int i = 0; i < tableauCount; i++) Pile(kind: PileKind.tableau),
    ];
    final List<Card> cards = deck.deal(deck.length);
    for (int i = 0; i < cards.length; i++) {
      final int col = firstTableau + (i % tableauCount);
      piles[col] = piles[col].add(cards[i].faceUpCard);
    }
    return piles;
  }

  @override
  bool isLegalMove(
    GameState state,
    int fromPile,
    List<Card> cards,
    int toPile,
  ) {
    if (cards.isEmpty || !isMovableSequence(cards)) {
      return false;
    }
    final Pile dest = state.pileAt(toPile);
    switch (dest.kind) {
      case PileKind.freecell:
        return cards.length == 1 && dest.isEmpty;
      case PileKind.foundation:
        if (cards.length != 1) {
          return false;
        }
        return stacksOnFoundation(cards.first, dest.topCard);
      case PileKind.tableau:
        if (cards.length > maxMovable(state, toPile: toPile)) {
          return false;
        }
        if (dest.isEmpty) {
          return true;
        }
        return stacksOnTableau(cards.first, dest.topCard!);
      case PileKind.stock:
      case PileKind.waste:
        return false;
    }
  }

  @override
  bool isWon(GameState state) {
    for (int i = firstFoundation; i < firstFoundation + foundationCount; i++) {
      if (state.pileAt(i).length != kingRank) {
        return false;
      }
    }
    return true;
  }

  @override
  List<int> autoTargets(GameState state, int fromPile, {int? cardIndex}) {
    final Pile source = state.pileAt(fromPile);
    if (source.isEmpty) {
      return const <int>[];
    }
    final int index = cardIndex ?? source.length - 1;
    if (index < 0 || index >= source.length) {
      return const <int>[];
    }
    final List<Card> moving = source.cards.sublist(index);
    final List<int> targets = <int>[];
    for (int to = 0; to < state.piles.length; to++) {
      if (to == fromPile) {
        continue;
      }
      if (isLegalMove(state, fromPile, moving, to)) {
        targets.add(to);
      }
    }
    return targets;
  }

  @override
  int maxMovable(GameState state, {int? toPile}) {
    int freeCells = 0;
    for (int i = firstFreecell; i < firstFreecell + freecellCount; i++) {
      if (state.pileAt(i).isEmpty) {
        freeCells++;
      }
    }
    int emptyColumns = 0;
    for (int i = firstTableau; i < firstTableau + tableauCount; i++) {
      if (state.pileAt(i).isEmpty) {
        emptyColumns++;
      }
    }
    if (toPile != null &&
        state.pileAt(toPile).kind == PileKind.tableau &&
        state.pileAt(toPile).isEmpty &&
        emptyColumns > 0) {
      emptyColumns--;
    }
    return (freeCells + 1) * (1 << emptyColumns);
  }
}
