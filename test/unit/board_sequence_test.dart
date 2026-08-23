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

  test(
    'CascadeSequence runs longer than a second and a half for a full win',
    () {
      const CascadeSequence c = CascadeSequence();
      final Duration total = c.totalFor(_won());
      expect(total, greaterThan(const Duration(milliseconds: 1800)));
    },
  );

  test('CascadeSequence rebounds to a meaningful height, not a token hop', () {
    const CascadeSequence c = CascadeSequence();
    final GameState won = _won();
    const CardKey king = CardKey(Suit.clubs, kingRank);
    final double floor = _board.height - _origin.bottom;
    bool touchedFloorOnce = false;
    double minDyAfterFirstBounce = floor;
    for (int ms = 0; ms <= 2500; ms += 5) {
      final double dy = c
          .offsetAt(king, Duration(milliseconds: ms), won, _origin, _board)
          .dy;
      if (!touchedFloorOnce) {
        if (dy >= floor - 5) {
          touchedFloorOnce = true;
        }
        continue;
      }
      if (dy < minDyAfterFirstBounce) {
        minDyAfterFirstBounce = dy;
      }
    }
    expect(
      minDyAfterFirstBounce,
      lessThan(floor * 0.6),
      reason: 'the rebound after the first bounce was too shallow',
    );
  });

  test('CascadeSequence offset is zero exactly at activation', () {
    const CascadeSequence c = CascadeSequence();
    final GameState won = _won();
    final Duration delay = c.delayFor(const CardKey(Suit.clubs, aceRank), won);
    expect(
      c.offsetAt(
        const CardKey(Suit.clubs, aceRank),
        delay,
        won,
        _origin,
        _board,
      ),
      Offset.zero,
    );
  });

  test('CascadeSequence never falls past the board floor', () {
    const CascadeSequence c = CascadeSequence();
    final GameState won = _won();
    const CardKey king = CardKey(Suit.clubs, kingRank);
    final double floor = _board.height - _origin.bottom;
    for (int ms = 0; ms <= 5000; ms += 25) {
      final double dy = c
          .offsetAt(king, Duration(milliseconds: ms), won, _origin, _board)
          .dy;
      expect(
        dy,
        lessThanOrEqualTo(floor + 0.5),
        reason: 'overshot the floor at $ms ms',
      );
    }
  });

  test('CascadeSequence bounces off the floor before settling', () {
    const CascadeSequence c = CascadeSequence();
    final GameState won = _won();
    const CardKey king = CardKey(Suit.clubs, kingRank);
    final double floor = _board.height - _origin.bottom;
    bool nearFloor = false;
    bool roseAwayAfter = false;
    for (int ms = 0; ms <= 1500; ms += 5) {
      final double dy = c
          .offsetAt(king, Duration(milliseconds: ms), won, _origin, _board)
          .dy;
      if (dy >= floor - 15) {
        nearFloor = true;
      } else if (nearFloor && dy <= floor - 50) {
        roseAwayAfter = true;
      }
    }
    expect(nearFloor, isTrue, reason: 'never reached the floor to bounce');
    expect(roseAwayAfter, isTrue, reason: 'never rebounded off the floor');
  });

  test('CascadeSequence settles at the floor well after activating', () {
    const CascadeSequence c = CascadeSequence();
    final GameState won = _won();
    const CardKey king = CardKey(Suit.clubs, kingRank);
    final double floor = _board.height - _origin.bottom;
    final double dy = c
        .offsetAt(king, const Duration(seconds: 10), won, _origin, _board)
        .dy;
    expect(dy, closeTo(floor, 0.5));
  });

  test(
    'CascadeSequence drifts opposite foundations in opposite directions',
    () {
      const CascadeSequence c = CascadeSequence();
      final GameState won = _won();
      const CardKey clubsKing = CardKey(Suit.clubs, kingRank);
      const CardKey heartsKing = CardKey(Suit.hearts, kingRank);
      final double clubsDx = c
          .offsetAt(
            clubsKing,
            const Duration(milliseconds: 400),
            won,
            _origin,
            _board,
          )
          .dx;
      final double heartsDx = c
          .offsetAt(
            heartsKing,
            const Duration(milliseconds: 400),
            won,
            _origin,
            _board,
          )
          .dx;
      expect(clubsDx.sign, isNot(heartsDx.sign));
    },
  );

  test('CascadeSequence horizontal drift grows over time', () {
    const CascadeSequence c = CascadeSequence();
    final GameState won = _won();
    const CardKey king = CardKey(Suit.clubs, kingRank);
    final double early = c
        .offsetAt(king, const Duration(milliseconds: 200), won, _origin, _board)
        .dx
        .abs();
    final double late = c
        .offsetAt(king, const Duration(milliseconds: 800), won, _origin, _board)
        .dx
        .abs();
    expect(late, greaterThan(early));
  });

  test(
    'CascadeSequence rotation is zero at activation and grows afterward',
    () {
      const CascadeSequence c = CascadeSequence();
      final GameState won = _won();
      const CardKey king = CardKey(Suit.clubs, kingRank);
      final Duration delay = c.delayFor(king, won);
      expect(c.rotationAt(king, delay, won), 0.0);
      final double early = c
          .rotationAt(king, delay + const Duration(milliseconds: 200), won)
          .abs();
      final double late = c
          .rotationAt(king, delay + const Duration(milliseconds: 800), won)
          .abs();
      expect(early, greaterThan(0.0));
      expect(late, greaterThan(early));
    },
  );
}

const Rect _origin = Rect.fromLTWH(50, 20, 64, 90);
const Size _board = Size(400, 800);

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
