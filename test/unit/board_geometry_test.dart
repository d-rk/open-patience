import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/presentation/board_geometry.dart';

Card _up(Suit s, int r) => Card(suit: s, rank: r, faceUp: true);

GameState _klondike() => GameState(
  piles: <Pile>[
    Pile(
      kind: PileKind.stock,
      cards: const <Card>[Card(suit: Suit.clubs, rank: 9)],
    ),
    Pile(kind: PileKind.waste),
    Pile(kind: PileKind.foundation, cards: <Card>[_up(Suit.clubs, aceRank)]),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.spades, 5)]),
    Pile(
      kind: PileKind.tableau,
      cards: <Card>[for (int r = kingRank; r >= 1; r--) _up(Suit.hearts, r)],
    ),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.diamonds, kingRank)]),
  ],
);

Rect _rectOf(BoardGeometry g, Suit s, int r) =>
    g.cards.firstWhere((CardPlacement p) => p.key == CardKey(s, r)).rect;

void main() {
  group('CardKey', () {
    test('identity ignores faceUp and equals by suit+rank', () {
      const CardKey a = CardKey(Suit.hearts, 5);
      final CardKey b = CardKey.of(
        const Card(suit: Suit.hearts, rank: 5, faceUp: true),
      );
      final CardKey c = CardKey.of(
        const Card(suit: Suit.hearts, rank: 5, faceUp: false),
      );
      expect(b, a);
      expect(c, a);
      expect(<CardKey>{a, b, c}.length, 1);
    });

    test('widgetKey is stable and distinct per card', () {
      expect(
        const CardKey(Suit.spades, 13).widgetKey,
        const CardKey(Suit.spades, 13).widgetKey,
      );
      expect(
        const CardKey(Suit.spades, 13).widgetKey ==
            const CardKey(Suit.clubs, 13).widgetKey,
        isFalse,
      );
    });
  });

  test('CardPlacement.key derives from its card', () {
    const CardPlacement p = CardPlacement(
      card: Card(suit: Suit.clubs, rank: 2, faceUp: true),
      pileIndex: 3,
      indexInPile: 0,
      isTop: true,
      rect: Rect.fromLTWH(0, 0, 10, 14),
    );
    expect(p.key, const CardKey(Suit.clubs, 2));
  });

  group('stacked geometry (portrait)', () {
    late BoardGeometry g;
    setUp(() {
      g = BoardGeometry.resolve(
        game: _klondike(),
        width: 400,
        height: 800,
        shortestSide: 400,
        isLandscape: false,
        wasteVisibleCount: 1,
      );
    });

    test('layout is portrait', () {
      expect(g.metrics.layout, BoardLayout.portrait);
    });

    test('foundations sit above the tableau', () {
      expect(
        _rectOf(g, Suit.clubs, aceRank).center.dy,
        lessThan(_rectOf(g, Suit.spades, 5).center.dy),
      );
    });

    test('every card fits inside the viewport height', () {
      for (final CardPlacement p in g.cards) {
        expect(p.rect.bottom, lessThanOrEqualTo(800 + 0.5));
        expect(p.rect.top, greaterThanOrEqualTo(-0.5));
      }
    });

    test('the longest fan descends within the viewport', () {
      expect(
        _rectOf(g, Suit.hearts, aceRank).bottom,
        lessThanOrEqualTo(800 + 0.5),
      );
      // Fanned: each deeper card is lower than the one above it.
      expect(
        _rectOf(g, Suit.hearts, aceRank).top,
        greaterThan(_rectOf(g, Suit.hearts, kingRank).top),
      );
    });

    test('empty piles produce slot placements, filled piles do not', () {
      final Set<int> slotPiles = g.slots
          .map((SlotPlacement s) => s.pileIndex)
          .toSet();
      expect(slotPiles.contains(3), isTrue); // empty foundation
      expect(slotPiles.contains(2), isFalse); // foundation with the ace
    });

    test('each pile has a drop-target rect covering its cards', () {
      expect(g.dropTargets.containsKey(7), isTrue);
      final Rect dt = g.dropTargets[7]!;
      expect(dt.contains(_rectOf(g, Suit.hearts, kingRank).center), isTrue);
      expect(dt.contains(_rectOf(g, Suit.hearts, aceRank).center), isTrue);
    });
  });

  group('stacked geometry (phone landscape)', () {
    test('fit-to-height: nothing overflows the short edge', () {
      final BoardGeometry g = BoardGeometry.resolve(
        game: _klondike(),
        width: 800,
        height: 360,
        shortestSide: 360,
        isLandscape: true,
        wasteVisibleCount: 1,
      );
      expect(g.metrics.layout, BoardLayout.phoneLandscape);
      for (final CardPlacement p in g.cards) {
        expect(p.rect.bottom, lessThanOrEqualTo(360 + 0.5));
      }
    });
  });

  group('waste fan', () {
    test('draw-3 waste fans the last three cards left-to-right', () {
      final GameState g3 = GameState(
        piles: <Pile>[
          Pile(kind: PileKind.stock),
          Pile(
            kind: PileKind.waste,
            cards: <Card>[
              _up(Suit.clubs, 2),
              _up(Suit.clubs, 3),
              _up(Suit.clubs, 4),
            ],
          ),
          Pile(kind: PileKind.foundation),
          Pile(kind: PileKind.foundation),
          Pile(kind: PileKind.foundation),
          Pile(kind: PileKind.foundation),
          for (int i = 0; i < 7; i++) Pile(kind: PileKind.tableau),
        ],
      );
      final BoardGeometry g = BoardGeometry.resolve(
        game: g3,
        width: 400,
        height: 800,
        shortestSide: 400,
        isLandscape: false,
        wasteVisibleCount: 3,
      );
      final double x2 = _rectOf(g, Suit.clubs, 2).left;
      final double x3 = _rectOf(g, Suit.clubs, 3).left;
      final double x4 = _rectOf(g, Suit.clubs, 4).left;
      expect(x3, greaterThan(x2));
      expect(x4, greaterThan(x3));
    });
  });
}
