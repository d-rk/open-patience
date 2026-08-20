import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/games/klondike.dart';
import 'package:open_patience/core/move.dart';
import 'package:open_patience/core/pile.dart';

Card _c(Suit s, int r, {bool up = true}) => Card(suit: s, rank: r, faceUp: up);

List<Pile> _board({
  List<Card> foundation2 = const <Card>[],
  List<Card> col6 = const <Card>[],
  List<Card> col7 = const <Card>[],
  List<Card> waste = const <Card>[],
}) {
  return <Pile>[
    Pile(kind: PileKind.stock),
    Pile(kind: PileKind.waste, cards: waste),
    Pile(kind: PileKind.foundation, cards: foundation2),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.tableau, cards: col6),
    Pile(kind: PileKind.tableau, cards: col7),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau),
  ];
}

void main() {
  final KlondikeRules rules = KlondikeRules(drawCount: 1);

  group('Klondike deal', () {
    test('deals 7 columns of increasing height with only the top face up', () {
      final GameState state = GameState.newGame(rules, seed: 123);
      for (int col = 0; col < KlondikeRules.tableauCount; col++) {
        final Pile pile = state.pileAt(KlondikeRules.firstTableau + col);
        expect(pile.length, col + 1);
        expect(pile.topCard!.faceUp, isTrue);
        for (int i = 0; i < pile.length - 1; i++) {
          expect(pile.cards[i].faceUp, isFalse);
        }
      }
      // 52 - (1+2+..+7) = 24 in the stock, all face down.
      expect(state.pileAt(KlondikeRules.stockIndex).length, 24);
      expect(
        state
            .pileAt(KlondikeRules.stockIndex)
            .cards
            .every((Card c) => !c.faceUp),
        isTrue,
      );
    });

    test('same seed deals an identical board', () {
      final GameState a = GameState.newGame(rules, seed: 9);
      final GameState b = GameState.newGame(rules, seed: 9);
      expect(a, equals(b));
    });
  });

  group('Klondike legal / illegal moves', () {
    test('red-on-black descending tableau move is legal', () {
      final GameState state = GameState(
        piles: _board(
          col6: <Card>[_c(Suit.hearts, 6)],
          col7: <Card>[_c(Suit.spades, 7)],
        ),
      );
      expect(
        rules.isLegalMove(state, 6, <Card>[_c(Suit.hearts, 6)], 7),
        isTrue,
      );
    });

    test('same-colour tableau move is rejected', () {
      final GameState state = GameState(
        piles: _board(
          col6: <Card>[_c(Suit.hearts, 6)],
          col7: <Card>[_c(Suit.diamonds, 7)],
        ),
      );
      expect(
        rules.isLegalMove(state, 6, <Card>[_c(Suit.hearts, 6)], 7),
        isFalse,
      );
    });

    test('only a King may move to an empty tableau column', () {
      final GameState state = GameState(
        piles: _board(col6: <Card>[_c(Suit.spades, 13)]),
      );
      expect(
        rules.isLegalMove(state, 6, <Card>[_c(Suit.spades, 13)], 8),
        isTrue,
      );
      final GameState state2 = GameState(
        piles: _board(col6: <Card>[_c(Suit.spades, 12)]),
      );
      expect(
        rules.isLegalMove(state2, 6, <Card>[_c(Suit.spades, 12)], 8),
        isFalse,
      );
    });

    test(
      'foundation accepts Ace then same-suit ascending, single card only',
      () {
        final GameState emptyFoundation = GameState(
          piles: _board(col6: <Card>[_c(Suit.clubs, 1)]),
        );
        expect(
          rules.isLegalMove(emptyFoundation, 6, <Card>[_c(Suit.clubs, 1)], 2),
          isTrue,
        );

        final GameState withAce = GameState(
          piles: _board(
            foundation2: <Card>[_c(Suit.clubs, 1)],
            col6: <Card>[_c(Suit.clubs, 2)],
          ),
        );
        expect(
          rules.isLegalMove(withAce, 6, <Card>[_c(Suit.clubs, 2)], 2),
          isTrue,
        );
        // Wrong suit onto the clubs foundation is rejected.
        final GameState wrongSuit = GameState(
          piles: _board(
            foundation2: <Card>[_c(Suit.clubs, 1)],
            col6: <Card>[_c(Suit.hearts, 2)],
          ),
        );
        expect(
          rules.isLegalMove(wrongSuit, 6, <Card>[_c(Suit.hearts, 2)], 2),
          isFalse,
        );
      },
    );

    test('a valid multi-card run moves; a broken run does not', () {
      final List<Card> run = <Card>[
        _c(Suit.spades, 8),
        _c(Suit.hearts, 7),
        _c(Suit.spades, 6),
      ];
      final GameState ok = GameState(
        piles: _board(col6: run, col7: <Card>[_c(Suit.diamonds, 9)]),
      );
      expect(rules.isLegalMove(ok, 6, run, 7), isTrue);

      final List<Card> broken = <Card>[_c(Suit.spades, 8), _c(Suit.spades, 7)];
      final GameState bad = GameState(
        piles: _board(col6: broken, col7: <Card>[_c(Suit.diamonds, 9)]),
      );
      expect(rules.isLegalMove(bad, 6, broken, 7), isFalse);
    });

    test('a face-down card cannot be moved', () {
      final GameState state = GameState(
        piles: _board(
          col6: <Card>[_c(Suit.hearts, 6, up: false)],
          col7: <Card>[_c(Suit.spades, 7)],
        ),
      );
      expect(
        rules.isLegalMove(state, 6, <Card>[_c(Suit.hearts, 6, up: false)], 7),
        isFalse,
      );
    });
  });

  group('Klondike draw count', () {
    test('draw-1 turns a single card; draw-3 turns three', () {
      final KlondikeRules draw1 = KlondikeRules(drawCount: 1);
      final KlondikeRules draw3 = KlondikeRules(drawCount: 3);
      final GameState s1 = GameState.newGame(draw1, seed: 5);
      final GameState s3 = GameState.newGame(draw3, seed: 5);

      s1.applyMove(draw1.buildDraw(s1)!);
      s3.applyMove(draw3.buildDraw(s3)!);

      expect(s1.pileAt(KlondikeRules.wasteIndex).length, 1);
      expect(s3.pileAt(KlondikeRules.wasteIndex).length, 3);
      expect(s1.pileAt(KlondikeRules.stockIndex).length, 23);
      expect(s3.pileAt(KlondikeRules.stockIndex).length, 21);
    });

    test('recycle returns the emptied stock from the waste', () {
      final KlondikeRules draw1 = KlondikeRules(drawCount: 1);
      final GameState state = GameState(
        piles: _board(waste: <Card>[_c(Suit.clubs, 4), _c(Suit.hearts, 9)]),
      );
      // Stock is empty, waste has two cards.
      final Move recycle = draw1.buildRecycle(state)!;
      state.applyMove(recycle);
      expect(state.pileAt(KlondikeRules.stockIndex).length, 2);
      expect(state.pileAt(KlondikeRules.wasteIndex).isEmpty, isTrue);
      expect(
        state
            .pileAt(KlondikeRules.stockIndex)
            .cards
            .every((Card c) => !c.faceUp),
        isTrue,
      );
    });

    test('recycle preserves draw order across passes', () {
      final KlondikeRules draw1 = KlondikeRules(drawCount: 1);
      final Card a = _c(Suit.spades, 1, up: false);
      final Card b = _c(Suit.spades, 2, up: false);
      final Card c = _c(Suit.spades, 3, up: false);
      // Stock bottom->top [a, b, c]; c is on top and drawn first.
      final List<Pile> piles = _board();
      piles[KlondikeRules.stockIndex] = Pile(
        kind: PileKind.stock,
        cards: <Card>[a, b, c],
      );
      final GameState state = GameState(piles: piles);

      final Card firstDrawn = state.pileAt(KlondikeRules.stockIndex).topCard!;
      state.applyMove(draw1.buildDraw(state)!);
      state.applyMove(draw1.buildDraw(state)!);
      state.applyMove(draw1.buildDraw(state)!);
      expect(state.pileAt(KlondikeRules.stockIndex).isEmpty, isTrue);

      state.applyMove(draw1.buildRecycle(state)!);

      // After flipping the waste back over, the next card drawn must be the
      // same one that was drawn first in the previous pass.
      final Card afterRecycleTop = state
          .pileAt(KlondikeRules.stockIndex)
          .topCard!;
      expect(afterRecycleTop.suit, firstDrawn.suit);
      expect(afterRecycleTop.rank, firstDrawn.rank);
    });

    test('buildDraw returns null on an empty stock', () {
      final GameState state = GameState(piles: _board());
      expect(rules.buildDraw(state), isNull);
    });
  });

  group('Klondike win detection', () {
    test('isWon is true only when all four foundations are complete', () {
      final GameState state = GameState.newGame(rules, seed: 1);
      expect(rules.isWon(state), isFalse);
      expect(rules.isWon(_wonState()), isTrue);
    });
  });

  group('Klondike autoTargets', () {
    test('an Ace on the waste offers its foundation as a destination', () {
      final GameState state = GameState(
        piles: _board(waste: <Card>[_c(Suit.clubs, 1)]),
      );
      final List<int> targets = rules.autoTargets(
        state,
        KlondikeRules.wasteIndex,
      );
      expect(targets, contains(2));
    });
  });
}

/// A fully-won Klondike board: four complete Ace..King foundations.
GameState _wonState() {
  List<Card> full(Suit s) => <Card>[
    for (int r = 1; r <= 13; r++) Card(suit: s, rank: r, faceUp: true),
  ];
  return GameState(
    piles: <Pile>[
      Pile(kind: PileKind.stock),
      Pile(kind: PileKind.waste),
      Pile(kind: PileKind.foundation, cards: full(Suit.clubs)),
      Pile(kind: PileKind.foundation, cards: full(Suit.diamonds)),
      Pile(kind: PileKind.foundation, cards: full(Suit.hearts)),
      Pile(kind: PileKind.foundation, cards: full(Suit.spades)),
      Pile(kind: PileKind.tableau),
      Pile(kind: PileKind.tableau),
      Pile(kind: PileKind.tableau),
      Pile(kind: PileKind.tableau),
      Pile(kind: PileKind.tableau),
      Pile(kind: PileKind.tableau),
      Pile(kind: PileKind.tableau),
    ],
  );
}
