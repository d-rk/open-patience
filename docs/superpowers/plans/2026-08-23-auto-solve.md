# Auto-Solve When Trivially Solvable Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Offer the player a one-press button that finishes the game as an animated cascade whenever the board has become trivially (greedily) solvable, without ever taking over manual play.

**Architecture:** A pure-Dart greedy solver in `core/` both detects trivial solvability and returns the exact winning move list. A tiny `GameRules.advanceStock` hook keeps stock-cycling behind the interface so the solver stays variant-agnostic. The `GameBloc` recomputes solvability on every board change (exposed as `canAutoSolve`) and, on an `AutoSolveRequested` event, replays the solution move-by-move on a timer so each card animates via the existing move animations, ending in the normal win path. A gold ✨ button in the top bar appears only while solvable.

**Tech Stack:** Flutter (latest stable), Dart, `flutter_bloc`, `equatable`, `flutter_test` / `bloc_test`.

**Spec:** `docs/superpowers/specs/2026-08-23-auto-solve-design.md`

## Global Constraints

- **TDD is mandatory** — no production code before a failing test (RED → GREEN → REFACTOR).
- **`lib/core/` and `lib/persistence/` never import `package:flutter`** — enforced by CI grep. The solver and `advanceStock` are pure Dart.
- **Rules live behind `GameRules`** — variant-specific stock behaviour goes in `advanceStock`, never a type-check in the solver or a widget.
- **Explicit static types on all public APIs.** Single quotes. Lines aim ≤ 80, hard ≤ 100. Trailing commas on multi-line. Run `dart format` before every commit.
- **Constants are lowerCamelCase `const`** (not `SCREAMING_CASE`).
- **Design tokens only** — widgets reference `GamePalette.*` / `GameFonts.*`, never hardcoded colors or font strings.
- Every commit must leave `flutter analyze` and `flutter test` green.

---

## File Structure

- **Create** `lib/core/solver.dart` — the greedy solver (`solveGreedy`), pure Dart, one responsibility: decide trivial solvability and produce the winning move list.
- **Create** `test/unit/solver_test.dart` — solver unit tests.
- **Modify** `lib/core/game_rules.dart` — add `Move? advanceStock(GameState state)` to the interface (+ `import 'move.dart';`).
- **Modify** `lib/core/games/klondike.dart` — implement `advanceStock`.
- **Modify** `lib/core/games/freecell.dart` — implement `advanceStock` (returns `null`).
- **Modify** `test/unit/klondike_test.dart`, `test/unit/freecell_test.dart` — `advanceStock` tests.
- **Modify** `lib/presentation/bloc/game_bloc_state.dart` — add `canAutoSolve` to `GameInProgress`.
- **Modify** `lib/presentation/bloc/game_event.dart` — add `AutoSolveRequested`.
- **Modify** `lib/presentation/bloc/game_bloc.dart` — solve-on-emit, cascade handler, `_solving` input guard, injectable step duration.
- **Modify** `test/unit/game_bloc_test.dart` — detection + cascade tests.
- **Modify** `lib/ui/top_bar.dart` — the solve button.
- **Modify** `test/widget/game_widget_test.dart` — button visibility + tap-drives-to-win.

---

## Task 1: `GameRules.advanceStock` hook

**Files:**
- Modify: `lib/core/game_rules.dart`
- Modify: `lib/core/games/klondike.dart`
- Modify: `lib/core/games/freecell.dart`
- Test: `test/unit/klondike_test.dart`, `test/unit/freecell_test.dart`

**Interfaces:**
- Consumes: existing `KlondikeRules.buildDraw`, `KlondikeRules.buildRecycle`.
- Produces: `Move? GameRules.advanceStock(GameState state)` — the next stock-cycling system move (draw, or recycle once the stock is exhausted), or `null` for variants with no stock / nothing to cycle. Applied by callers with `GameState.applyMove`.

- [ ] **Step 1: Write the failing tests**

Add to `test/unit/klondike_test.dart` (inside `main()`):

```dart
group('advanceStock', () {
  test('draws from a non-empty stock, then recycles once exhausted', () {
    final KlondikeRules rules = KlondikeRules(drawCount: 1);
    final GameState state = GameState.newGame(rules, seed: 3);
    // Fresh deal: stock is full, so advanceStock is a draw (stock -> waste).
    final Move? draw = rules.advanceStock(state);
    expect(draw, isNotNull);
    expect(draw!.fromPile, KlondikeRules.stockIndex);
    expect(draw.toPile, KlondikeRules.wasteIndex);

    // Drain the stock entirely; advanceStock must then recycle waste -> stock.
    Move? next = rules.advanceStock(state);
    while (next != null && next.fromPile == KlondikeRules.stockIndex) {
      state.applyMove(next);
      next = rules.advanceStock(state);
    }
    expect(next, isNotNull);
    expect(next!.fromPile, KlondikeRules.wasteIndex);
    expect(next.toPile, KlondikeRules.stockIndex);
  });
});
```

Add to `test/unit/freecell_test.dart` (inside `main()`):

```dart
group('advanceStock', () {
  test('returns null — FreeCell has no stock to cycle', () {
    final FreecellRules rules = FreecellRules();
    final GameState state = GameState.newGame(rules, seed: 3);
    expect(rules.advanceStock(state), isNull);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/klondike_test.dart test/unit/freecell_test.dart`
Expected: FAIL — `advanceStock` is not defined on `GameRules`.

- [ ] **Step 3: Add the interface method**

In `lib/core/game_rules.dart`, add the import and the abstract method. Add near the top with the other imports:

```dart
import 'move.dart';
```

Add this method inside the `abstract class GameRules` (after `maxMovable`):

```dart
  /// A system move that cycles the stock to expose new cards (a draw, or a
  /// recycle once the stock is exhausted), or `null` for variants with no
  /// stock or nothing left to cycle. Used by the auto-solver to reach buried
  /// cards. Apply with [GameState.applyMove].
  Move? advanceStock(GameState state);
```

- [ ] **Step 4: Implement in Klondike**

In `lib/core/games/klondike.dart`, add this override (place it with the other `@override` methods, e.g. after `maxMovable`):

```dart
  @override
  Move? advanceStock(GameState state) =>
      buildDraw(state) ?? buildRecycle(state);
```

- [ ] **Step 5: Implement in FreeCell**

In `lib/core/games/freecell.dart`, add this override (after `maxMovable`):

```dart
  @override
  Move? advanceStock(GameState state) => null;
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/unit/klondike_test.dart test/unit/freecell_test.dart`
Expected: PASS.

- [ ] **Step 7: Verify the whole suite and format**

Run: `dart format lib test && flutter analyze && flutter test`
Expected: no format diff, no analyzer issues, all tests PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/core/game_rules.dart lib/core/games/klondike.dart lib/core/games/freecell.dart test/unit/klondike_test.dart test/unit/freecell_test.dart
git commit -m "feat(core): add GameRules.advanceStock stock-cycling hook"
```

---

## Task 2: `solveGreedy` — the greedy solver

**Files:**
- Create: `lib/core/solver.dart`
- Test: `test/unit/solver_test.dart`

**Interfaces:**
- Consumes: `GameState.copy`, `GameState.applyMove`, `GameState.pileAt`, `GameState.piles`; `GameRules.isWon`, `GameRules.autoTargets`, `GameRules.advanceStock` (Task 1); `Pile.topCard`, `Pile.kind`, `PileKind.foundation`; `Move`.
- Produces: `List<Move>? solveGreedy(GameState state, GameRules rules)` — the ordered winning move list, or `null` if the board is not trivially solvable. Does not mutate `state`.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/solver_test.dart`:

```dart
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
          Pile(kind: PileKind.stock, cards: <Card>[
            for (int r = kingRank; r >= aceRank; r--)
              Card(suit: Suit.spades, rank: r),
          ]),
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/solver_test.dart`
Expected: FAIL — `solver.dart` / `solveGreedy` does not exist.

- [ ] **Step 3: Implement the solver**

Create `lib/core/solver.dart`:

```dart
import 'card.dart';
import 'game_rules.dart';
import 'game_state.dart';
import 'move.dart';
import 'pile.dart';

/// Greedily auto-finishes [state] under [rules]: repeatedly send any card whose
/// top is a legal foundation move to that foundation, cycling the stock (via
/// [GameRules.advanceStock]) when nothing else is playable, until the game is
/// won or progress stalls.
///
/// Returns the ordered list of moves that wins, or `null` if the board cannot
/// be trivially finished this way. Operates on a clone; [state] is not mutated.
/// The returned moves, applied in order to a board equal to [state], reproduce
/// the winning trajectory.
List<Move>? solveGreedy(GameState state, GameRules rules) {
  final GameState work = state.copy();
  final List<Move> solution = <Move>[];
  int cyclesSinceProgress = 0;
  // Secondary safety net against a logic error; a real solve is < 200 moves.
  const int hardCap = 100000;

  for (int ops = 0; ops < hardCap; ops++) {
    if (rules.isWon(work)) {
      return solution;
    }
    final Move? foundationMove = _nextFoundationMove(work, rules);
    if (foundationMove != null) {
      work.applyMove(foundationMove);
      solution.add(foundationMove);
      cyclesSinceProgress = 0;
      continue;
    }
    final Move? cycle = rules.advanceStock(work);
    if (cycle == null) {
      return null;
    }
    // A stock draw/recycle keeps the stock+waste total constant, so two full
    // passes over it with no foundation move means the loop is stuck.
    final int deckLeft = _stockPlusWaste(work);
    if (cyclesSinceProgress > 2 * deckLeft + 2) {
      return null;
    }
    work.applyMove(cycle);
    solution.add(cycle);
    cyclesSinceProgress++;
  }
  return null;
}

/// The first legal single-card move onto a foundation, scanning piles in
/// canonical order, or `null` if none exists.
Move? _nextFoundationMove(GameState state, GameRules rules) {
  for (int from = 0; from < state.piles.length; from++) {
    final Pile pile = state.pileAt(from);
    if (pile.isEmpty || pile.kind == PileKind.foundation) {
      continue;
    }
    for (final int to in rules.autoTargets(state, from)) {
      if (state.pileAt(to).kind == PileKind.foundation) {
        return Move(
          fromPile: from,
          toPile: to,
          cards: <Card>[pile.topCard!],
        );
      }
    }
  }
  return null;
}

int _stockPlusWaste(GameState state) {
  int total = 0;
  for (final Pile pile in state.piles) {
    if (pile.kind == PileKind.stock || pile.kind == PileKind.waste) {
      total += pile.length;
    }
  }
  return total;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/unit/solver_test.dart`
Expected: PASS (all six cases).

- [ ] **Step 5: Verify boundary, format, full suite**

Run: `! grep -rl "package:flutter" lib/core lib/persistence && dart format lib test && flutter analyze && flutter test`
Expected: the grep prints nothing and exits success (no Flutter import leaked), no format diff, no analyzer issues, all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/solver.dart test/unit/solver_test.dart
git commit -m "feat(core): add greedy auto-solver (solveGreedy)"
```

---

## Task 3: Bloc detection — `canAutoSolve`

**Files:**
- Modify: `lib/presentation/bloc/game_bloc_state.dart`
- Modify: `lib/presentation/bloc/game_bloc.dart`
- Test: `test/unit/game_bloc_test.dart`

**Interfaces:**
- Consumes: `solveGreedy` (Task 2).
- Produces: `GameInProgress.canAutoSolve` (`bool`, default `false`) — `true` iff the current board is trivially solvable. Every in-progress emission from the bloc carries it.

- [ ] **Step 1: Write the failing tests**

Add to `test/unit/game_bloc_test.dart`. It already imports `KlondikeRules`, `_klondikeBoard`, `_run`, `_up`, `_FakeRepo`, `_bloc`. Add inside `main()`:

```dart
group('canAutoSolve detection', () {
  test('false for an ordinary in-progress board', () {
    final GameState state = _klondikeBoard(
      col6: <Card>[_up(Suit.spades, 7)],
      col7: <Card>[_up(Suit.hearts, 8)],
    );
    final GameBloc bloc = _bloc(_FakeRepo(), state);
    addTearDown(bloc.close);
    final GameBlocState s = bloc.state;
    expect(s, isA<GameInProgress>());
    expect((s as GameInProgress).canAutoSolve, isFalse);
  });

  test('true once the board is greedily solvable', () {
    // Three suits complete, spades A..Q on foundation, K of spades in a column.
    final GameState state = _klondikeBoard(
      foundationClubs: _run(Suit.clubs, 13),
      foundationDiamonds: _run(Suit.diamonds, 13),
      foundationHearts: _run(Suit.hearts, 13),
      foundationSpades: _run(Suit.spades, 12),
      col6: <Card>[_up(Suit.spades, 13)],
    );
    final GameBloc bloc = _bloc(_FakeRepo(), state);
    addTearDown(bloc.close);
    expect((bloc.state as GameInProgress).canAutoSolve, isTrue);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/game_bloc_test.dart -n "canAutoSolve detection"`
Expected: FAIL — `GameInProgress` has no `canAutoSolve` member.

- [ ] **Step 3: Add the state field**

In `lib/presentation/bloc/game_bloc_state.dart`, replace the `GameInProgress` class with:

```dart
/// A game still being played. [canAutoSolve] is `true` when the board is
/// trivially (greedily) solvable, which drives the top-bar solve button.
class GameInProgress extends GameBlocState {
  const GameInProgress(super.state, {this.canAutoSolve = false});

  final bool canAutoSolve;

  @override
  List<Object?> get props => <Object?>[state, canAutoSolve];
}
```

- [ ] **Step 4: Compute the flag in the bloc**

In `lib/presentation/bloc/game_bloc.dart`:

Add the import near the other core imports:

```dart
import '../../core/solver.dart';
```

Change the `_snapshotOf` in-progress branch to compute the flag. Replace:

```dart
    return GameInProgress(state.copy());
```

with:

```dart
    return GameInProgress(
      state.copy(),
      canAutoSolve: solveGreedy(state, rules) != null,
    );
```

Now route every in-progress emission through `_snapshotOf` so all of them carry the flag. Make these replacements:

- In `_emitAfterMove`, the `else` branch — replace `emit(GameInProgress(_state.copy()));` with `emit(_snapshotOf(_state, rules));`
- In `_onTick` — replace `emit(GameInProgress(_state.copy()));` with `emit(_snapshotOf(_state, rules));`
- In `_onNewDealRequested` — replace `emit(GameInProgress(_state.copy()));` with `emit(_snapshotOf(_state, rules));`
- In `_onRestartDealRequested` — replace `emit(GameInProgress(_state.copy()));` with `emit(_snapshotOf(_state, rules));`

(`_onUndoRequested` and `_onRedoRequested` already emit `_snapshotOf(_state, rules)`, so they pick up the flag automatically.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/unit/game_bloc_test.dart -n "canAutoSolve detection"`
Expected: PASS.

- [ ] **Step 6: Run the full bloc suite (guard against regressions)**

Run: `flutter test test/unit/game_bloc_test.dart`
Expected: PASS — existing move/undo/win tests still green (the added prop is `false` by default so equality matchers on `GameInProgress` are unaffected).

- [ ] **Step 7: Format + analyze**

Run: `dart format lib test && flutter analyze`
Expected: no diff, no issues.

- [ ] **Step 8: Commit**

```bash
git add lib/presentation/bloc/game_bloc_state.dart lib/presentation/bloc/game_bloc.dart test/unit/game_bloc_test.dart
git commit -m "feat(bloc): expose canAutoSolve on in-progress state"
```

---

## Task 4: Bloc cascade — `AutoSolveRequested`

**Files:**
- Modify: `lib/presentation/bloc/game_event.dart`
- Modify: `lib/presentation/bloc/game_bloc.dart`
- Test: `test/unit/game_bloc_test.dart`

**Interfaces:**
- Consumes: `solveGreedy` (Task 2), `GameState.applyMove`, `GameState.isWon`, `_snapshotOf`, `repository.recordResult`, `repository.clearSave`.
- Produces: `AutoSolveRequested` event; a `_solving` guard that makes player-input handlers no-ops during the cascade; a constructor-injectable `Duration autoSolveStep` (default 120 ms) for the per-move delay.

- [ ] **Step 1: Write the failing tests**

Add to `test/unit/game_bloc_test.dart`. Update the `_bloc` helper to accept the step duration so tests run instantly — change it to:

```dart
GameBloc _bloc(
  _FakeRepo repo,
  GameState state, {
  int seed = 7,
  Duration autoSolveStep = Duration.zero,
}) {
  return GameBloc(
    variant: 'klondike-draw1',
    repository: repo,
    seed: seed,
    state: state,
    random: Random(1),
    autoSolveStep: autoSolveStep,
  );
}
```

Then add inside `main()`:

```dart
group('AutoSolveRequested', () {
  GameState solvableBoard() => _klondikeBoard(
    foundationClubs: _run(Suit.clubs, 13),
    foundationDiamonds: _run(Suit.diamonds, 13),
    foundationHearts: _run(Suit.hearts, 13),
    foundationSpades: _run(Suit.spades, 12),
    col6: <Card>[_up(Suit.spades, 13)],
  );

  blocTest<GameBloc, GameBlocState>(
    'plays the solution out to a recorded win',
    build: () => _bloc(_FakeRepo(), solvableBoard()),
    act: (GameBloc bloc) => bloc.add(const AutoSolveRequested()),
    expect: () => <Matcher>[isA<GameWon>()],
    verify: (GameBloc bloc) {
      final _FakeRepo repo = bloc.repository as _FakeRepo;
      expect(
        repo.calls.any((String c) => c.startsWith('record:klondike-draw1:true')),
        isTrue,
      );
      expect(repo.calls.contains('clear:klondike-draw1'), isTrue);
    },
  );

  blocTest<GameBloc, GameBlocState>(
    'is a no-op on a board that is not solvable',
    build: () => _bloc(
      _FakeRepo(),
      _klondikeBoard(
        col6: <Card>[_up(Suit.spades, 7)],
        col7: <Card>[_up(Suit.hearts, 8)],
      ),
    ),
    act: (GameBloc bloc) => bloc.add(const AutoSolveRequested()),
    expect: () => <Matcher>[],
  );
});
```

Note: `_FakeRepo` exposes `calls`; `bloc.repository` is public on `GameBloc`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/game_bloc_test.dart -n "AutoSolveRequested"`
Expected: FAIL — `AutoSolveRequested` and the `autoSolveStep` parameter don't exist.

- [ ] **Step 3: Add the event**

In `lib/presentation/bloc/game_event.dart`, add at the end (before the final closing content / after `SaveRequested`):

```dart
/// Play the board out to a win via the auto-solver. A no-op unless the board
/// is trivially solvable.
class AutoSolveRequested extends GameEvent {
  const AutoSolveRequested();
}
```

- [ ] **Step 4: Add the injectable step duration and register the handler**

In `lib/presentation/bloc/game_bloc.dart`, add the constructor parameter. Change the primary constructor signature to accept it and store it. In the `GameBloc({...})` parameter list add:

```dart
    this.autoSolveStep = const Duration(milliseconds: 120),
```

Add the field with the other final fields (near `final Random _random;`):

```dart
  /// Delay between moves while the auto-solver cascade plays out.
  final Duration autoSolveStep;

  bool _solving = false;
```

In the constructor body, register the handler alongside the others:

```dart
    on<AutoSolveRequested>(_onAutoSolveRequested);
```

Also thread `autoSolveStep` through the `GameBloc.newGame` factory: add `Duration autoSolveStep = const Duration(milliseconds: 120),` to its parameters and pass `autoSolveStep: autoSolveStep,` in the returned `GameBloc(...)`.

- [ ] **Step 5: Implement the cascade handler**

In `lib/presentation/bloc/game_bloc.dart`, add this handler (place it after `_onSaveRequested`):

```dart
  Future<void> _onAutoSolveRequested(
    AutoSolveRequested event,
    Emitter<GameBlocState> emit,
  ) async {
    if (_solving) {
      return;
    }
    final List<Move>? solution = solveGreedy(_state, rules);
    if (solution == null) {
      return;
    }
    _solving = true;
    try {
      for (final Move move in solution) {
        _state.applyMove(move);
        if (_state.isWon(rules)) {
          final int elapsed = _state.elapsedSeconds;
          final int moves = _state.moveCount;
          await repository.recordResult(
            variant: variant,
            won: true,
            timeSeconds: elapsed,
            moves: moves,
          );
          await repository.clearSave(variant);
          emit(GameWon(_state.copy(), elapsed: elapsed, moves: moves));
          return;
        }
        emit(_snapshotOf(_state, rules));
        await Future<void>.delayed(autoSolveStep);
      }
    } finally {
      _solving = false;
    }
  }
```

- [ ] **Step 6: Add the input guard to player-input handlers**

In `lib/presentation/bloc/game_bloc.dart`, add `if (_solving) return;` as the first line of each of these handlers: `_onMoveRequested`, `_onTapMoveRequested`, `_onDoubleTapRequested`, `_onUndoRequested`, `_onRedoRequested`. Do **not** add it to `_onTick` (the timer keeps running during the cascade). Example for `_onUndoRequested`:

```dart
  Future<void> _onUndoRequested(
    UndoRequested event,
    Emitter<GameBlocState> emit,
  ) async {
    if (_solving) {
      return;
    }
    if (!_state.canUndo) {
      return;
    }
    _state.undo();
    ...
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/unit/game_bloc_test.dart -n "AutoSolveRequested"`
Expected: PASS.

- [ ] **Step 8: Run the full bloc suite**

Run: `flutter test test/unit/game_bloc_test.dart`
Expected: PASS (the `_bloc` helper default `autoSolveStep: Duration.zero` doesn't affect existing tests).

- [ ] **Step 9: Format + analyze**

Run: `dart format lib test && flutter analyze`
Expected: no diff, no issues.

- [ ] **Step 10: Commit**

```bash
git add lib/presentation/bloc/game_event.dart lib/presentation/bloc/game_bloc.dart test/unit/game_bloc_test.dart
git commit -m "feat(bloc): animated auto-solve cascade via AutoSolveRequested"
```

---

## Task 5: Top-bar solve button

**Files:**
- Modify: `lib/ui/top_bar.dart`
- Test: `test/widget/game_widget_test.dart`

**Interfaces:**
- Consumes: `GameInProgress.canAutoSolve` (Task 3), `AutoSolveRequested` (Task 4), `GamePalette.gold`.
- Produces: a gold `Icons.auto_fix_high` `IconButton` with tooltip `'Solve'`, rendered in the top bar only while `canAutoSolve`, dispatching `const AutoSolveRequested()`.

- [ ] **Step 1: Write the failing tests**

Add to `test/widget/game_widget_test.dart` (it already has `_up`, `_run`, `_board`, `_pump`, and a bloc builder around line 64). Add inside `main()`:

```dart
group('auto-solve button', () {
  GameState solvable() => _board(
    foundationClubs: _run(Suit.clubs, 13),
    foundationDiamonds: _run(Suit.diamonds, 13),
    foundationHearts: _run(Suit.hearts, 13),
    foundationSpades: _run(Suit.spades, 12),
    col6: <Card>[_up(Suit.spades, 13)],
  );

  testWidgets('is absent when the board is not solvable', (
    WidgetTester tester,
  ) async {
    final GameBloc bloc = GameBloc(
      variant: 'klondike-draw1',
      repository: SharedPrefsRecordsRepository(await _prefs()),
      seed: 1,
      state: _board(
        col6: <Card>[_up(Suit.spades, 7)],
        col7: <Card>[_up(Suit.hearts, 8)],
      ),
      autoSolveStep: Duration.zero,
    );
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    expect(find.byTooltip('Solve'), findsNothing);
  });

  testWidgets('appears when solvable and drives to the win screen', (
    WidgetTester tester,
  ) async {
    final GameBloc bloc = GameBloc(
      variant: 'klondike-draw1',
      repository: SharedPrefsRecordsRepository(await _prefs()),
      seed: 1,
      state: solvable(),
      autoSolveStep: Duration.zero,
    );
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    expect(find.byTooltip('Solve'), findsOneWidget);

    await tester.tap(find.byTooltip('Solve'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordsScreen), findsOneWidget);
  });
});
```

If the file has no `_prefs()` helper, use whatever the existing tests use to construct a `SharedPrefsRecordsRepository` (grep the file for `SharedPrefs`/`SharedPreferences.setMockInitialValues` and mirror it — several existing tests already build a repo the same way; reuse that exact helper instead of inventing one).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/widget/game_widget_test.dart -n "auto-solve button"`
Expected: FAIL — no widget with tooltip `'Solve'`.

- [ ] **Step 3: Add the button to the top bar**

In `lib/ui/top_bar.dart`, extend the existing right-side `BlocBuilder`. Replace the whole `BlocBuilder<GameBloc, GameBlocState>( buildWhen: ..., builder: ... )` block with:

```dart
        BlocBuilder<GameBloc, GameBlocState>(
          buildWhen: (GameBlocState p, GameBlocState c) =>
              p.state.canUndo != c.state.canUndo ||
              p.state.canRedo != c.state.canRedo ||
              _canSolve(p) != _canSolve(c),
          builder: (BuildContext context, GameBlocState state) {
            return Row(
              children: <Widget>[
                if (_canSolve(state))
                  IconButton(
                    tooltip: 'Solve',
                    color: GamePalette.gold,
                    icon: const Icon(Icons.auto_fix_high),
                    onPressed: () => bloc.add(const AutoSolveRequested()),
                  ),
                IconButton(
                  tooltip: 'Undo',
                  color: GamePalette.gold,
                  icon: const Icon(Icons.undo),
                  onPressed: state.state.canUndo
                      ? () => bloc.add(const UndoRequested())
                      : null,
                ),
                IconButton(
                  tooltip: 'Redo',
                  color: GamePalette.gold,
                  icon: const Icon(Icons.redo),
                  onPressed: state.state.canRedo
                      ? () => bloc.add(const RedoRequested())
                      : null,
                ),
              ],
            );
          },
        ),
```

Add this private helper at the bottom of `top_bar.dart`'s `TopBar` class or as a top-level function in the file:

```dart
bool _canSolve(GameBlocState state) =>
    state is GameInProgress && state.canAutoSolve;
```

`top_bar.dart` already imports `game_bloc.dart`, `game_bloc_state.dart`, `game_event.dart`, and `game_palette.dart`, so `GameInProgress`, `AutoSolveRequested`, and `GamePalette.gold` are all in scope.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/widget/game_widget_test.dart -n "auto-solve button"`
Expected: PASS (both cases).

- [ ] **Step 5: Full suite, boundary, format, analyze**

Run: `! grep -rl "package:flutter" lib/core lib/persistence && dart format lib test && flutter analyze && flutter test`
Expected: grep prints nothing (success), no format diff, no analyzer issues, all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/top_bar.dart test/widget/game_widget_test.dart
git commit -m "feat(ui): show a solve button when the board is auto-solvable"
```

---

## Final verification

- [ ] Run the complete gate exactly as CI does:

```bash
flutter pub get
flutter analyze
! grep -rl "package:flutter" lib/core lib/persistence
flutter test
```

Expected: analyze clean, the grep exits success printing nothing, the whole suite green.

- [ ] Manually sanity-check on a device/emulator: play a Klondike deal to the point where all cards are exposed, confirm the ✨ button appears beside undo/redo, press it, and watch the cascade run to the win/records screen. (`flutter run --flavor production`)

---

## Self-Review notes (author)

- **Spec coverage:** greedy solver (Task 2) ✓; `advanceStock` behind the seam (Task 1) ✓; `canAutoSolve` recomputed per state (Task 3) ✓; animated cascade + normal-win recording + input guard + injectable step (Task 4) ✓; top-bar gold button shown only when solvable (Task 5) ✓; all test tiers from the spec covered across Tasks 1–5 ✓.
- **Type consistency:** `solveGreedy(GameState, GameRules) -> List<Move>?`, `GameRules.advanceStock(GameState) -> Move?`, `GameInProgress.canAutoSolve`, `AutoSolveRequested`, `GameBloc.autoSolveStep` are used identically everywhere they appear.
- **Latch decision:** implemented as reactive recompute (not a latched flag), per the spec's "always truthful" rationale.
