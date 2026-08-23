import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/games/klondike.dart';
import 'package:open_patience/core/move.dart';
import 'package:open_patience/core/pile.dart';

Card _c(Suit s, int r, {bool up = true}) => Card(suit: s, rank: r, faceUp: up);

/// A Klondike-shaped 13-pile board with two tableau columns overridable.
List<Pile> _klondikePiles({
  List<Card> col6 = const <Card>[],
  List<Card> col7 = const <Card>[],
  List<Card> stock = const <Card>[],
}) {
  return <Pile>[
    Pile(kind: PileKind.stock, cards: stock),
    Pile(kind: PileKind.waste),
    Pile(kind: PileKind.foundation),
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

  group('GameState.newGame', () {
    test('almostWon deals the near-win layout instead of a real shuffle', () {
      final GameState state = GameState.newGame(
        rules,
        seed: 1,
        almostWon: true,
      );
      expect(state, equals(GameState(piles: rules.dealAlmostWon())));
      expect(rules.isWon(state), isFalse);
    });

    test('almostWon defaults to false, preserving the seeded real deal', () {
      final GameState withDefault = GameState.newGame(rules, seed: 5);
      final GameState explicitFalse = GameState.newGame(
        rules,
        seed: 5,
        almostWon: false,
      );
      expect(withDefault, equals(explicitFalse));
    });
  });

  group('GameState move / undo / redo', () {
    test(
      'a legal move applies, then undo restores an exact prior snapshot',
      () {
        final GameState state = GameState(
          piles: _klondikePiles(
            col6: <Card>[_c(Suit.hearts, 6)],
            col7: <Card>[_c(Suit.spades, 7)],
          ),
        );
        final GameState before = state.copy();

        final bool moved = state.tryMove(
          Move(fromPile: 6, toPile: 7, cards: <Card>[_c(Suit.hearts, 6)]),
          rules,
        );

        expect(moved, isTrue);
        expect(state == before, isFalse, reason: 'board changed');
        expect(state.moveCount, 1);

        state.undo();
        expect(state, equals(before), reason: 'exact prior snapshot');
        expect(state.moveCount, 0);
      },
    );

    test('redo returns to the exact post-move state', () {
      final GameState state = GameState(
        piles: _klondikePiles(
          col6: <Card>[_c(Suit.hearts, 6)],
          col7: <Card>[_c(Suit.spades, 7)],
        ),
      );
      state.tryMove(
        Move(fromPile: 6, toPile: 7, cards: <Card>[_c(Suit.hearts, 6)]),
        rules,
      );
      final GameState afterMove = state.copy();
      state.undo();
      state.redo();
      expect(state, equals(afterMove));
      expect(state.moveCount, 1);
    });

    test('an illegal move is a no-op returning false (never throws)', () {
      final GameState state = GameState(
        piles: _klondikePiles(
          col6: <Card>[_c(Suit.hearts, 6)],
          col7: <Card>[_c(Suit.clubs, 6)],
        ),
      );
      final GameState before = state.copy();
      final bool moved = state.tryMove(
        Move(fromPile: 6, toPile: 7, cards: <Card>[_c(Suit.hearts, 6)]),
        rules,
      );
      expect(moved, isFalse);
      expect(state, equals(before));
      expect(state.canUndo, isFalse);
    });

    test(
      'exposing a face-down tableau card auto-flips it, and undo re-hides it',
      () {
        final GameState state = GameState(
          piles: _klondikePiles(
            col6: <Card>[_c(Suit.clubs, 9, up: false), _c(Suit.hearts, 6)],
            col7: <Card>[_c(Suit.spades, 7)],
          ),
        );
        final GameState before = state.copy();

        state.tryMove(
          Move(fromPile: 6, toPile: 7, cards: <Card>[_c(Suit.hearts, 6)]),
          rules,
        );
        // The 9 that was under the 6 is now exposed and flipped face up.
        expect(state.pileAt(6).topCard, _c(Suit.clubs, 9, up: true));

        state.undo();
        expect(
          state,
          equals(before),
          reason: 'the auto-flipped card is turned back face down on undo',
        );
        // The 6 is back on top and the 9 beneath it is face down again.
        expect(state.pileAt(6).topCard, _c(Suit.hearts, 6, up: true));
        expect(state.pileAt(6).cards.first, _c(Suit.clubs, 9, up: false));
      },
    );

    test('applyMove drives a stock draw and undo reverses it exactly', () {
      final GameState state = GameState(
        piles: _klondikePiles(
          stock: <Card>[
            _c(Suit.clubs, 4, up: false),
            _c(Suit.hearts, 9, up: false),
          ],
        ),
      );
      final GameState before = state.copy();
      final Move draw = rules.buildDraw(state)!;
      state.applyMove(draw);

      expect(state.pileAt(0).length, 1, reason: 'one card left in stock');
      expect(state.pileAt(1).topCard!.faceUp, isTrue, reason: 'drawn face up');

      state.undo();
      expect(state, equals(before), reason: 'draw reverses to the exact deal');
    });
  });

  group('GameState serialization', () {
    test('toJson -> fromJson yields an equal GameState (with history)', () {
      final GameState state = GameState(
        piles: _klondikePiles(
          col6: <Card>[_c(Suit.hearts, 6)],
          col7: <Card>[_c(Suit.spades, 7)],
        ),
      );
      state.tryMove(
        Move(fromPile: 6, toPile: 7, cards: <Card>[_c(Suit.hearts, 6)]),
        rules,
      );
      state.tick(42);

      final GameState restored = GameState.fromJson(state.toJson());
      expect(restored, equals(state));
      expect(restored.elapsedSeconds, 42);
      // Stacks are excluded from equality, so assert them explicitly to give
      // their serialization teeth.
      expect(restored.canUndo, state.canUndo);
      expect(restored.undoCount, state.undoCount);
      restored.undo();
      expect(
        restored.pileAt(6).topCard,
        _c(Suit.hearts, 6),
        reason: 'undo history survived the round trip',
      );
    });
  });
}
