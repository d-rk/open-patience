import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/presentation/board_geometry.dart';
import 'package:open_patience/presentation/board_sequence.dart';
import 'package:open_patience/ui/theme/game_motion.dart';

Card _up(Suit s, int r) => Card(suit: s, rank: r, faceUp: true);

GameState _dealt() => GameState(
  piles: <Pile>[
    Pile(kind: PileKind.stock),
    Pile(kind: PileKind.waste),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.spades, 5)]),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.hearts, 8)]),
    for (int i = 0; i < 5; i++) Pile(kind: PileKind.tableau),
  ],
);

void main() {
  test('DealSequence matches the first render', () {
    expect(const DealSequence().matches(null, _dealt()), isTrue);
  });

  test('DealSequence does not match an ordinary move', () {
    final GameState a = _dealt();
    expect(const DealSequence().matches(a, a), isFalse);
  });

  test('later cards in deal order get longer delays', () {
    const DealSequence s = DealSequence();
    final BoardGeometry g = BoardGeometry.resolve(
      game: _dealt(),
      width: 400,
      height: 800,
      shortestSide: 400,
      isLandscape: false,
      wasteVisibleCount: 1,
    );
    final Duration d5 = s.delayFor(const CardKey(Suit.spades, 5), g);
    final Duration d8 = s.delayFor(const CardKey(Suit.hearts, 8), g);
    expect(d5, isNot(equals(d8)));
    expect(s.totalFor(g), greaterThanOrEqualTo(GameMotion.move));
  });

  test('deal total scales to the animated-card count, not a fixed 52', () {
    const DealSequence s = DealSequence();
    final BoardGeometry g = BoardGeometry.resolve(
      game: _dealt(),
      width: 400,
      height: 800,
      shortestSide: 400,
      isLandscape: false,
      wasteVisibleCount: 1,
    );
    // _dealt lays out only its two tableau cards (empty stock/waste/foundations
    // show as slots), so the controller is sized for those, not a full deck.
    final Duration expected =
        GameMotion.dealStagger * (g.cards.length - 1) + GameMotion.move;
    expect(s.totalFor(g), expected);
    final Duration fullDeck = GameMotion.dealStagger * 51 + GameMotion.move;
    expect(s.totalFor(g), lessThan(fullDeck));
  });

  test('CascadeSequence delays deeper foundation cards more than the top', () {
    const CascadeSequence c = CascadeSequence();
    final GameState won = _won();
    final Duration ace = c.delayFor(const CardKey(Suit.clubs, aceRank), won);
    final Duration king = c.delayFor(const CardKey(Suit.clubs, kingRank), won);
    expect(king, Duration.zero);
    expect(ace, greaterThan(king));
  });

  test(
    'CascadeSequence delays the same rank across foundations identically',
    () {
      const CascadeSequence c = CascadeSequence();
      final GameState won = _won();
      final Duration clubsQueen = c.delayFor(
        const CardKey(Suit.clubs, 12),
        won,
      );
      final Duration heartsQueen = c.delayFor(
        const CardKey(Suit.hearts, 12),
        won,
      );
      expect(clubsQueen, heartsQueen);
    },
  );

  test('CascadeSequence ignores a card not in a foundation pile', () {
    const CascadeSequence c = CascadeSequence();
    final GameState mid = _dealt();
    expect(c.delayFor(const CardKey(Suit.spades, 5), mid), Duration.zero);
  });

  test('CascadeSequence total scales with the deepest foundation pile', () {
    const CascadeSequence c = CascadeSequence();
    final Duration total = c.totalFor(_won());
    expect(
      total,
      CascadeSequence.stagger * (kingRank - aceRank) + CascadeSequence.flight,
    );
  });

  test('CascadeSequence offset is zero before a card activates', () {
    const CascadeSequence c = CascadeSequence();
    final GameState won = _won();
    final Duration delay = c.delayFor(const CardKey(Suit.clubs, aceRank), won);
    expect(
      c.offsetAt(
        const CardKey(Suit.clubs, aceRank),
        delay,
        won,
        const Size(400, 800),
      ),
      Offset.zero,
    );
  });

  test('CascadeSequence falls clear of the board once a flight completes', () {
    const CascadeSequence c = CascadeSequence();
    final GameState won = _won();
    const Size board = Size(400, 800);
    final Duration end =
        c.delayFor(const CardKey(Suit.clubs, kingRank), won) +
        CascadeSequence.flight;
    final Offset offset = c.offsetAt(
      const CardKey(Suit.clubs, kingRank),
      end,
      won,
      board,
    );
    expect(offset.dy, greaterThan(board.height));
  });

  test('CascadeSequence holds its landed offset past the flight end', () {
    const CascadeSequence c = CascadeSequence();
    final GameState won = _won();
    const Size board = Size(400, 800);
    final Duration end =
        c.delayFor(const CardKey(Suit.clubs, kingRank), won) +
        CascadeSequence.flight;
    final Offset atEnd = c.offsetAt(
      const CardKey(Suit.clubs, kingRank),
      end,
      won,
      board,
    );
    final Offset wellPast = c.offsetAt(
      const CardKey(Suit.clubs, kingRank),
      end + const Duration(seconds: 5),
      won,
      board,
    );
    expect(wellPast, atEnd);
  });

  test(
    'CascadeSequence rotation is zero before activation and non-zero after',
    () {
      const CascadeSequence c = CascadeSequence();
      final GameState won = _won();
      const CardKey king = CardKey(Suit.clubs, kingRank);
      final Duration delay = c.delayFor(king, won);
      expect(c.rotationAt(king, delay, won), 0.0);
      expect(
        c.rotationAt(king, delay + CascadeSequence.flight, won),
        isNot(0.0),
      );
    },
  );
}

/// A fully-won board: all four foundations run Ace..King.
GameState _won() => GameState(
  piles: <Pile>[
    Pile(kind: PileKind.stock),
    Pile(kind: PileKind.waste),
    for (final Suit s in Suit.values)
      Pile(
        kind: PileKind.foundation,
        cards: <Card>[for (int r = aceRank; r <= kingRank; r++) _up(s, r)],
      ),
    for (int i = 0; i < 7; i++) Pile(kind: PileKind.tableau),
  ],
);
