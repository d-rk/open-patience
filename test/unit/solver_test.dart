import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/games/freecell.dart';
import 'package:open_patience/core/games/klondike.dart';
import 'package:open_patience/core/move.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/core/solver.dart';

Card _up(Suit s, int r) => Card(suit: s, rank: r, faceUp: true);
List<Card> _run(Suit s, int maxRank) => <Card>[
  for (int r = aceRank; r <= maxRank; r++) _up(s, r),
];

/// Applies [moves] in order to a copy of [state] and returns the result.
GameState _replay(GameState state, List<Move> moves) {
  final GameState work = state.copy();
  for (final Move move in moves) {
    work.applyMove(move);
  }
  return work;
}

void main() {
  group('solveGreedy — Klondike', () {
    test('solvable endgame: four Kings finish onto full foundations', () {
      final KlondikeRules rules = KlondikeRules(drawCount: 1);
      final GameState state = GameState(
        piles: <Pile>[
          Pile(kind: PileKind.stock),
          Pile(kind: PileKind.waste),
          Pile(kind: PileKind.foundation, cards: _run(Suit.clubs, 12)),
          Pile(kind: PileKind.foundation, cards: _run(Suit.diamonds, 12)),
          Pile(kind: PileKind.foundation, cards: _run(Suit.hearts, 12)),
          Pile(kind: PileKind.foundation, cards: _run(Suit.spades, 12)),
          Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.clubs, 13)]),
          Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.diamonds, 13)]),
          Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.hearts, 13)]),
          Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.spades, 13)]),
          Pile(kind: PileKind.tableau),
          Pile(kind: PileKind.tableau),
          Pile(kind: PileKind.tableau),
        ],
      );
      final List<Move>? moves = solveGreedy(state, rules);
      expect(moves, isNotNull);
      expect(moves!.length, 4);
      expect(rules.isWon(_replay(state, moves)), isTrue);
    });

    test('solvable via stock cycling: the last suit is buried in the stock', () {
      final KlondikeRules rules = KlondikeRules(drawCount: 1);
      // Three suits are done; all 13 spades sit face-down in the stock with the
      // Ace on top, so only stock draws can surface them. buildDraw flips them
      // face up as they move to the waste.
      final GameState state = GameState(
        piles: <Pile>[
          Pile(
            kind: PileKind.stock,
            cards: <Card>[
              for (int r = kingRank; r >= aceRank; r--)
                Card(suit: Suit.spades, rank: r),
            ],
          ),
          Pile(kind: PileKind.waste),
          Pile(kind: PileKind.foundation, cards: _run(Suit.clubs, 13)),
          Pile(kind: PileKind.foundation, cards: _run(Suit.diamonds, 13)),
          Pile(kind: PileKind.foundation, cards: _run(Suit.hearts, 13)),
          Pile(kind: PileKind.foundation),
          for (int i = 0; i < 7; i++) Pile(kind: PileKind.tableau),
        ],
      );
      final List<Move>? moves = solveGreedy(state, rules);
      expect(moves, isNotNull);
      expect(rules.isWon(_replay(state, moves!)), isTrue);
    });

    test('unsolvable mid-game board returns null', () {
      final KlondikeRules rules = KlondikeRules(drawCount: 1);
      // No aces available anywhere; nothing can advance a foundation.
      final GameState state = GameState(
        piles: <Pile>[
          Pile(kind: PileKind.stock),
          Pile(kind: PileKind.waste),
          Pile(kind: PileKind.foundation),
          Pile(kind: PileKind.foundation),
          Pile(kind: PileKind.foundation),
          Pile(kind: PileKind.foundation),
          Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.spades, 7)]),
          Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.hearts, 8)]),
          Pile(kind: PileKind.tableau),
          Pile(kind: PileKind.tableau),
          Pile(kind: PileKind.tableau),
          Pile(kind: PileKind.tableau),
          Pile(kind: PileKind.tableau),
        ],
      );
      expect(solveGreedy(state, rules), isNull);
    });

    test('does not mutate the input state', () {
      final KlondikeRules rules = KlondikeRules(drawCount: 1);
      final GameState state = GameState(
        piles: <Pile>[
          Pile(kind: PileKind.stock),
          Pile(kind: PileKind.waste),
          Pile(kind: PileKind.foundation, cards: _run(Suit.clubs, 12)),
          Pile(kind: PileKind.foundation, cards: _run(Suit.diamonds, 12)),
          Pile(kind: PileKind.foundation, cards: _run(Suit.hearts, 12)),
          Pile(kind: PileKind.foundation, cards: _run(Suit.spades, 12)),
          Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.clubs, 13)]),
          Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.diamonds, 13)]),
          Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.hearts, 13)]),
          Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.spades, 13)]),
          Pile(kind: PileKind.tableau),
          Pile(kind: PileKind.tableau),
          Pile(kind: PileKind.tableau),
        ],
      );
      final GameState before = state.copy();
      solveGreedy(state, rules);
      expect(state, before);
    });
  });

  group('solveGreedy — FreeCell', () {
    test('auto-finishable with cards still parked in free cells', () {
      final FreecellRules rules = FreecellRules();
      final GameState state = GameState(
        piles: <Pile>[
          Pile(kind: PileKind.freecell, cards: <Card>[_up(Suit.clubs, 13)]),
          Pile(kind: PileKind.freecell, cards: <Card>[_up(Suit.diamonds, 13)]),
          Pile(kind: PileKind.freecell, cards: <Card>[_up(Suit.hearts, 13)]),
          Pile(kind: PileKind.freecell, cards: <Card>[_up(Suit.spades, 13)]),
          Pile(kind: PileKind.foundation, cards: _run(Suit.clubs, 12)),
          Pile(kind: PileKind.foundation, cards: _run(Suit.diamonds, 12)),
          Pile(kind: PileKind.foundation, cards: _run(Suit.hearts, 12)),
          Pile(kind: PileKind.foundation, cards: _run(Suit.spades, 12)),
          for (int i = 0; i < 8; i++) Pile(kind: PileKind.tableau),
        ],
      );
      final List<Move>? moves = solveGreedy(state, rules);
      expect(moves, isNotNull);
      expect(rules.isWon(_replay(state, moves!)), isTrue);
    });
  });
}
