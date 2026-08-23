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

GameState _freecell() => GameState(
  piles: <Pile>[
    Pile(kind: PileKind.freecell, cards: <Card>[_up(Suit.spades, 7)]),
    Pile(kind: PileKind.freecell),
    Pile(kind: PileKind.freecell),
    Pile(kind: PileKind.freecell),
    Pile(kind: PileKind.foundation, cards: <Card>[_up(Suit.clubs, aceRank)]),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    for (int i = 0; i < 8; i++) Pile(kind: PileKind.tableau),
  ],
);

/// A 6-cell (relaxed) FreeCell board: 6 free cells + 4 foundations + 8 tableau,
/// whose 6 + 4 top overflows a single portrait row and splits into two.
GameState _freecell6() => GameState(
  piles: <Pile>[
    Pile(kind: PileKind.freecell, cards: <Card>[_up(Suit.spades, 7)]),
    for (int i = 0; i < 5; i++) Pile(kind: PileKind.freecell),
    Pile(kind: PileKind.foundation, cards: <Card>[_up(Suit.clubs, aceRank)]),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    for (int i = 0; i < 8; i++) Pile(kind: PileKind.tableau),
  ],
);

Rect _rectOf(BoardGeometry g, Suit s, int r) =>
    g.cards.firstWhere((CardPlacement p) => p.key == CardKey(s, r)).rect;

Rect _trayOf(BoardGeometry g, TrayKind kind) =>
    g.trays.firstWhere((TrayPlacement t) => t.kind == kind).rect;

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

  group('tablet-landscape geometry', () {
    test('foundations sit to the right of the last tableau column', () {
      final BoardGeometry g = BoardGeometry.resolve(
        game: _klondike(),
        width: 1200,
        height: 800,
        shortestSide: 800,
        isLandscape: true,
        wasteVisibleCount: 1,
      );
      expect(g.metrics.layout, BoardLayout.tabletLandscape);
      expect(
        _rectOf(g, Suit.clubs, aceRank).center.dx,
        greaterThan(_rectOf(g, Suit.diamonds, kingRank).center.dx),
      );
    });

    test('free cells sit left of the foundations', () {
      final BoardGeometry g = BoardGeometry.resolve(
        game: _freecell(),
        width: 1200,
        height: 800,
        shortestSide: 800,
        isLandscape: true,
        wasteVisibleCount: 1,
      );
      expect(
        _rectOf(g, Suit.spades, 7).center.dx,
        lessThan(_rectOf(g, Suit.clubs, aceRank).center.dx),
      );
    });

    test('nothing overflows the viewport', () {
      final BoardGeometry g = BoardGeometry.resolve(
        game: _klondike(),
        width: 1200,
        height: 800,
        shortestSide: 800,
        isLandscape: true,
        wasteVisibleCount: 1,
      );
      for (final CardPlacement p in g.cards) {
        expect(p.rect.right, lessThanOrEqualTo(1200 + 0.5));
        expect(p.rect.bottom, lessThanOrEqualTo(800 + 0.5));
      }
    });
  });

  group('zone trays', () {
    test('portrait single-row top: a foundation tray and a parking tray '
        'wrap their groups, above the tableau', () {
      final BoardGeometry g = BoardGeometry.resolve(
        game: _klondike(),
        width: 400,
        height: 800,
        shortestSide: 400,
        isLandscape: false,
        wasteVisibleCount: 1,
      );
      expect(g.trays.length, 2);
      expect(g.trays.map((TrayPlacement t) => t.kind).toSet(), <TrayKind>{
        TrayKind.foundation,
        TrayKind.parking,
      });
      final Rect foundationTray = _trayOf(g, TrayKind.foundation);
      final Rect parkingTray = _trayOf(g, TrayKind.parking);
      // Each tray wraps its own group's cards.
      expect(
        foundationTray.contains(_rectOf(g, Suit.clubs, aceRank).center),
        isTrue,
      );
      expect(
        parkingTray.contains(_rectOf(g, Suit.clubs, 9).center), // stock card
        isTrue,
      );
      // The foundation tray does not wrap the parking group's card.
      expect(
        foundationTray.contains(_rectOf(g, Suit.clubs, 9).center),
        isFalse,
      );
      // Trays sit above the tableau (single row: side by side, same top).
      expect(
        foundationTray.bottom,
        lessThanOrEqualTo(_rectOf(g, Suit.spades, 5).top + 0.5),
      );
      expect((foundationTray.top - parkingTray.top).abs(), lessThan(0.5));
      // Side by side, not overlapping.
      expect(parkingTray.right, lessThanOrEqualTo(foundationTray.left + 0.5));
    });

    test('portrait two-row top (6-cell FreeCell): the foundation tray stacks '
        'above the parking tray without overlap', () {
      final BoardGeometry g = BoardGeometry.resolve(
        game: _freecell6(),
        width: 400,
        height: 800,
        shortestSide: 400,
        isLandscape: false,
        wasteVisibleCount: 1,
      );
      expect(g.trays.length, 2);
      final Rect foundationTray = _trayOf(g, TrayKind.foundation);
      final Rect parkingTray = _trayOf(g, TrayKind.parking);
      expect(foundationTray.center.dy, lessThan(parkingTray.center.dy));
      expect(foundationTray.bottom, lessThanOrEqualTo(parkingTray.top + 0.5));
      // The parked free cell lives in the parking tray, the ace in the
      // foundation tray.
      expect(parkingTray.contains(_rectOf(g, Suit.spades, 7).center), isTrue);
      expect(
        foundationTray.contains(_rectOf(g, Suit.clubs, aceRank).center),
        isTrue,
      );
    });

    test('tablet landscape: the parking tray sits left of the foundation '
        'tray, both within the viewport', () {
      final BoardGeometry g = BoardGeometry.resolve(
        game: _freecell(),
        width: 1200,
        height: 800,
        shortestSide: 800,
        isLandscape: true,
        wasteVisibleCount: 1,
      );
      expect(g.trays.length, 2);
      final Rect foundationTray = _trayOf(g, TrayKind.foundation);
      final Rect parkingTray = _trayOf(g, TrayKind.parking);
      expect(parkingTray.right, lessThanOrEqualTo(foundationTray.left + 0.5));
      expect(foundationTray.right, lessThanOrEqualTo(1200 + 0.5));
      expect(parkingTray.contains(_rectOf(g, Suit.spades, 7).center), isTrue);
      expect(
        foundationTray.contains(_rectOf(g, Suit.clubs, aceRank).center),
        isTrue,
      );
    });
  });

  group('revealFoundationStacks', () {
    test('off by default: only the top card of a foundation is placed', () {
      final BoardGeometry g = BoardGeometry.resolve(
        game: _klondike(),
        width: 400,
        height: 800,
        shortestSide: 400,
        isLandscape: false,
        wasteVisibleCount: 1,
      );
      expect(g.cards.where((CardPlacement p) => p.pileIndex == 2).length, 1);
    });

    test('on: every card in a foundation pile is placed, at the same rect', () {
      final GameState game = _klondikeMultiFoundationCards();
      final BoardGeometry g = BoardGeometry.resolve(
        game: game,
        width: 400,
        height: 800,
        shortestSide: 400,
        isLandscape: false,
        wasteVisibleCount: 1,
        revealFoundationStacks: true,
      );
      final List<CardPlacement> stack = g.cards
          .where((CardPlacement p) => p.pileIndex == 2)
          .toList();
      expect(stack.length, 2);
      expect(stack[0].rect, stack[1].rect);
      expect(stack.where((CardPlacement p) => p.isTop).length, 1);
    });

    test('on: a non-foundation pile still places only its visible cards', () {
      final GameState game = _klondikeMultiFoundationCards();
      final BoardGeometry g = BoardGeometry.resolve(
        game: game,
        width: 400,
        height: 800,
        shortestSide: 400,
        isLandscape: false,
        wasteVisibleCount: 1,
        revealFoundationStacks: true,
      );
      // The stock pile still places only its one visible top card either way.
      expect(g.cards.where((CardPlacement p) => p.pileIndex == 0).length, 1);
    });

    test('on: an empty foundation still produces a slot, not a card', () {
      final GameState game = _klondike();
      final BoardGeometry g = BoardGeometry.resolve(
        game: game,
        width: 400,
        height: 800,
        shortestSide: 400,
        isLandscape: false,
        wasteVisibleCount: 1,
        revealFoundationStacks: true,
      );
      expect(g.cards.where((CardPlacement p) => p.pileIndex == 3), isEmpty);
      expect(g.slots.where((SlotPlacement s) => s.pileIndex == 3).length, 1);
    });
  });
}

/// [_klondike] with a second card stacked on the clubs foundation, so a
/// foundation pile has more than one card to reveal.
GameState _klondikeMultiFoundationCards() {
  final GameState base = _klondike();
  final List<Pile> piles = List<Pile>.of(base.piles);
  piles[2] = Pile(
    kind: PileKind.foundation,
    cards: <Card>[_up(Suit.clubs, aceRank), _up(Suit.clubs, 2)],
  );
  return GameState(piles: piles);
}
