import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/games/freecell.dart';
import 'package:open_patience/core/pile.dart';

Card _c(Suit s, int r) => Card(suit: s, rank: r, faceUp: true);

/// A FreeCell-shaped 16-pile board. Free cells 0..3, foundations 4..7,
/// tableau 8..15.
List<Pile> _board({
  Map<int, List<Card>> freecells = const <int, List<Card>>{},
  Map<int, List<Card>> tableau = const <int, List<Card>>{},
}) {
  final List<Pile> piles = <Pile>[
    for (int i = 0; i < 4; i++)
      Pile(kind: PileKind.freecell, cards: freecells[i] ?? const <Card>[]),
    for (int i = 0; i < 4; i++) Pile(kind: PileKind.foundation),
    for (int i = 0; i < 8; i++)
      Pile(kind: PileKind.tableau, cards: tableau[8 + i] ?? const <Card>[]),
  ];
  return piles;
}

void main() {
  final FreecellRules rules = FreecellRules();

  group('FreeCell deal', () {
    test('deals all 52 cards face up across 8 columns (7,7,7,7,6,6,6,6)', () {
      final GameState state = GameState.newGame(rules, seed: 77);
      final List<int> heights = <int>[
        for (int i = 0; i < 8; i++)
          state.pileAt(FreecellRules.firstTableau + i).length,
      ];
      expect(heights, <int>[7, 7, 7, 7, 6, 6, 6, 6]);
      final int total = heights.reduce((int a, int b) => a + b);
      expect(total, 52);
      for (int i = 0; i < 8; i++) {
        final Pile pile = state.pileAt(FreecellRules.firstTableau + i);
        expect(pile.cards.every((Card c) => c.faceUp), isTrue);
      }
      // Free cells and foundations start empty.
      for (int i = 0; i < 4; i++) {
        expect(state.pileAt(FreecellRules.firstFreecell + i).isEmpty, isTrue);
        expect(state.pileAt(FreecellRules.firstFoundation + i).isEmpty, isTrue);
      }
    });
  });

  group('FreeCell legal / illegal moves', () {
    test('a single card moves to an empty free cell; a pair does not', () {
      final GameState state = GameState(
        piles: _board(
          tableau: <int, List<Card>>{
            8: <Card>[_c(Suit.hearts, 7), _c(Suit.spades, 6)],
          },
        ),
      );
      expect(
        rules.isLegalMove(state, 8, <Card>[_c(Suit.spades, 6)], 0),
        isTrue,
      );
      expect(
        rules.isLegalMove(state, 8, <Card>[
          _c(Suit.hearts, 7),
          _c(Suit.spades, 6),
        ], 0),
        isFalse,
      );
    });

    test('any card may move onto an empty tableau column', () {
      final GameState state = GameState(
        piles: _board(
          tableau: <int, List<Card>>{
            8: <Card>[_c(Suit.hearts, 5)],
          },
        ),
      );
      expect(
        rules.isLegalMove(state, 8, <Card>[_c(Suit.hearts, 5)], 9),
        isTrue,
      );
    });

    test('tableau stacking requires alternating colour, descending', () {
      final GameState ok = GameState(
        piles: _board(
          tableau: <int, List<Card>>{
            8: <Card>[_c(Suit.spades, 6)],
            9: <Card>[_c(Suit.hearts, 7)],
          },
        ),
      );
      expect(rules.isLegalMove(ok, 8, <Card>[_c(Suit.spades, 6)], 9), isTrue);
      final GameState bad = GameState(
        piles: _board(
          tableau: <int, List<Card>>{
            8: <Card>[_c(Suit.spades, 6)],
            9: <Card>[_c(Suit.clubs, 7)],
          },
        ),
      );
      expect(rules.isLegalMove(bad, 8, <Card>[_c(Suit.spades, 6)], 9), isFalse);
    });
  });

  group('FreeCell maxMovable math', () {
    test('all cells and columns free: (freeCells+1) * 2^emptyColumns', () {
      // 3 free cells free, columns 8 & 9 hold cards, 10..15 empty -> 6 empty.
      final GameState state = GameState(
        piles: _board(
          freecells: <int, List<Card>>{
            0: <Card>[_c(Suit.hearts, 1)],
          },
          tableau: <int, List<Card>>{
            8: <Card>[_c(Suit.spades, 5)],
            9: <Card>[_c(Suit.hearts, 9)],
          },
        ),
      );
      // freeCells = 3, emptyColumns = 6 -> 4 * 64 = 256.
      expect(rules.maxMovable(state), (3 + 1) * (1 << 6));
    });

    test('moving onto an empty column does not let that column help', () {
      // No free cells occupied (4 free), columns: 8 has cards, 9..15 empty (7).
      final GameState state = GameState(
        piles: _board(
          tableau: <int, List<Card>>{
            8: <Card>[_c(Suit.spades, 5)],
          },
        ),
      );
      // Generic capacity: 5 * 2^7. Onto empty column 9: 5 * 2^6.
      expect(rules.maxMovable(state), (4 + 1) * (1 << 7));
      expect(rules.maxMovable(state, toPile: 9), (4 + 1) * (1 << 6));
    });

    test('a group larger than capacity is rejected for a tableau move', () {
      // Zero free cells, zero empty columns -> capacity 1.
      final GameState state = GameState(
        piles: _board(
          freecells: <int, List<Card>>{
            0: <Card>[_c(Suit.hearts, 1)],
            1: <Card>[_c(Suit.hearts, 2)],
            2: <Card>[_c(Suit.hearts, 3)],
            3: <Card>[_c(Suit.hearts, 4)],
          },
          tableau: <int, List<Card>>{
            for (int i = 8; i < 16; i++) i: <Card>[_c(Suit.clubs, 10)],
            8: <Card>[_c(Suit.spades, 8), _c(Suit.hearts, 7)],
            9: <Card>[_c(Suit.clubs, 9)],
          },
        ),
      );
      final List<Card> pair = <Card>[_c(Suit.spades, 8), _c(Suit.hearts, 7)];
      expect(rules.maxMovable(state), 1);
      expect(rules.isLegalMove(state, 8, pair, 9), isFalse);
    });
  });

  group('FreeCell win detection', () {
    test('isWon only when the four foundations are complete', () {
      final GameState fresh = GameState.newGame(rules, seed: 3);
      expect(rules.isWon(fresh), isFalse);

      List<Card> full(Suit s) => <Card>[
        for (int r = 1; r <= 13; r++) Card(suit: s, rank: r, faceUp: true),
      ];
      final GameState won = GameState(
        piles: <Pile>[
          for (int i = 0; i < 4; i++) Pile(kind: PileKind.freecell),
          Pile(kind: PileKind.foundation, cards: full(Suit.clubs)),
          Pile(kind: PileKind.foundation, cards: full(Suit.diamonds)),
          Pile(kind: PileKind.foundation, cards: full(Suit.hearts)),
          Pile(kind: PileKind.foundation, cards: full(Suit.spades)),
          for (int i = 0; i < 8; i++) Pile(kind: PileKind.tableau),
        ],
      );
      expect(rules.isWon(won), isTrue);
    });
  });
}
