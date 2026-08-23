import 'dart:math';

import '../card.dart';
import '../deck.dart';
import '../game_rules.dart';
import '../game_state.dart';
import '../move.dart';
import '../pile.dart';
import 'sequence.dart';

/// Klondike solitaire, supporting both draw-1 and draw-3 via [drawCount].
///
/// Pile layout (canonical index order):
/// * `0`        — stock
/// * `1`        — waste
/// * `2`..`5`   — foundations (one per suit, built up Ace..King)
/// * `6`..`12`  — seven tableau columns
class KlondikeRules implements GameRules {
  KlondikeRules({this.drawCount = 1})
    : assert(drawCount == 1 || drawCount == 3, 'drawCount must be 1 or 3');

  static const int stockIndex = 0;
  static const int wasteIndex = 1;
  static const int firstFoundation = 2;
  static const int foundationCount = 4;
  static const int firstTableau = 6;
  static const int tableauCount = 7;

  final int drawCount;

  @override
  String get id => 'klondike-draw$drawCount';

  @override
  List<Pile> deal(Deck deck) {
    final List<Pile> piles = <Pile>[
      Pile(kind: PileKind.stock),
      Pile(kind: PileKind.waste),
      for (int i = 0; i < foundationCount; i++) Pile(kind: PileKind.foundation),
    ];
    for (int col = 0; col < tableauCount; col++) {
      final List<Card> dealt = deck.deal(col + 1);
      final List<Card> column = <Card>[
        for (int i = 0; i < dealt.length; i++)
          i == dealt.length - 1 ? dealt[i].faceUpCard : dealt[i].faceDownCard,
      ];
      piles.add(Pile(kind: PileKind.tableau, cards: column));
    }
    piles[stockIndex] = Pile(
      kind: PileKind.stock,
      cards: deck.deal(deck.length).map((Card c) => c.faceDownCard).toList(),
    );
    return piles;
  }

  @override
  List<Pile> dealAlmostWon() {
    List<Card> aceToQueen(Suit suit) => <Card>[
      for (int rank = aceRank; rank < kingRank; rank++)
        Card(suit: suit, rank: rank, faceUp: true),
    ];
    return <Pile>[
      Pile(kind: PileKind.stock),
      Pile(kind: PileKind.waste),
      for (final Suit suit in Suit.values)
        Pile(kind: PileKind.foundation, cards: aceToQueen(suit)),
      for (final Suit suit in Suit.values)
        Pile(
          kind: PileKind.tableau,
          cards: <Card>[Card(suit: suit, rank: kingRank, faceUp: true)],
        ),
      for (int i = 0; i < tableauCount - Suit.values.length; i++)
        Pile(kind: PileKind.tableau),
    ];
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
      case PileKind.foundation:
        if (cards.length != 1) {
          return false;
        }
        return stacksOnFoundation(cards.first, dest.topCard);
      case PileKind.tableau:
        if (dest.isEmpty) {
          return cards.first.rank == kingRank;
        }
        return stacksOnTableau(cards.first, dest.topCard!);
      case PileKind.stock:
      case PileKind.waste:
      case PileKind.freecell:
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
  int maxMovable(GameState state, {int? toPile}) => kingRank;

  /// A stock->waste draw of up to [drawCount] cards, or `null` when the stock
  /// is empty. Apply it with [GameState.applyMove].
  Move? buildDraw(GameState state) {
    final Pile stock = state.pileAt(stockIndex);
    if (stock.isEmpty) {
      return null;
    }
    final int n = min(drawCount, stock.length);
    final List<Card> faceUp = stock
        .topN(n)
        .map((Card c) => c.faceUpCard)
        .toList();
    return Move(
      fromPile: stockIndex,
      toPile: wasteIndex,
      cards: faceUp,
      flipMovedCards: true,
    );
  }

  /// A waste->stock recycle once the stock is exhausted, or `null` when there
  /// is nothing to recycle. Apply it with [GameState.applyMove].
  Move? buildRecycle(GameState state) {
    final Pile stock = state.pileAt(stockIndex);
    final Pile waste = state.pileAt(wasteIndex);
    if (stock.isNotEmpty || waste.isEmpty) {
      return null;
    }
    // Flipping the waste pile back over reverses its order: the card drawn
    // first this pass ends up on top of the fresh stock, ready to be drawn
    // first again.
    final List<Card> faceDown = waste
        .topN(waste.length)
        .reversed
        .map((Card c) => c.faceDownCard)
        .toList();
    return Move(
      fromPile: wasteIndex,
      toPile: stockIndex,
      cards: faceDown,
      flipMovedCards: true,
    );
  }
}
