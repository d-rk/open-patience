# Auto-Solve When Trivially Solvable — Design

**Date:** 2026-08-23
**Status:** Approved design, pre-implementation
**Framework:** Flutter (latest stable)
**Language:** Dart

## Purpose

Once a game reaches the point where finishing it is pure busywork — every
remaining card just has to march up to the foundations — the player should
be offered a button that finishes it for them. Pressing it plays the ending
out as an animated cascade.

The button is an *offer*, never a takeover: the player may keep solving by
hand for as long as they like. From the moment the game becomes trivially
solvable, the button is available and stays available so it can be pressed
at any time.

## Scope

**In**
- A pure-Dart greedy solver in `core/` that both *detects* trivial
  solvability and *produces* the exact winning move sequence.
- One small `GameRules` interface addition (`advanceStock`) so the solver
  stays variant-agnostic.
- Bloc support: recompute solvability after each board change, expose it as
  `canAutoSolve`, and an `AutoSolveRequested` event that plays the solution
  out as an animated, move-by-move cascade ending in the normal win path.
- A gold ✨ "solve" button in the top bar, shown only while solvable.

**Explicitly out**
- A full search solver that answers "is this deal winnable at all?" We only
  detect *trivial* (greedy) solvability — the "you've basically won" state.
- Any change to the structural feel of manual play, gestures, or the win
  screen/records flow beyond feeding one more win into it.
- A hint system, partial auto-play, or "auto-play safe cards" toggle.

## Definition of "trivially solvable"

A board is trivially solvable iff a **greedy auto-finish wins it**: starting
from the current board, repeatedly

1. send any single card whose top is a legal foundation move to that
   foundation, and
2. when no foundation move exists, cycle the stock (draw / recycle) to
   expose new cards,

until the game is won. If that process reaches a won state, the board is
trivially solvable and the moves it took *are* the solution. If it stalls
(no foundation move available and cycling the whole stock exposes nothing
playable), the board is not trivially solvable.

This is outcome-based rather than a hand-coded structural heuristic, so it
is automatically correct for every variant, it is maximally permissive
(the button appears as early as an auto-finish can possibly succeed,
including FreeCell endgames with cards still parked in free cells), and — the
decisive point — the loop that decides solvability is the same loop that
produces the move list we need for the cascade. Detection and solution are
one computation.

### Why greedy is sufficient and never lies

Because foundation moves only ever *remove* the lowest exposed card of a
pile, greedy auto-finish never paints itself into a corner on a board it
reports as solvable: the solver actually simulates to a won state before it
answers "yes", so a `true` is a constructive proof. A `false` only means
"not *trivially* finishable"; it makes no claim about deeper winnability,
which is out of scope.

## Architecture

Strict layering is preserved. New/changed pieces by layer:

```
core/         solver.dart (new, pure Dart)
              game_rules.dart  (+ advanceStock)
              games/klondike.dart, games/freecell.dart (implement advanceStock)
presentation/ bloc/game_event.dart      (+ AutoSolveRequested)
              bloc/game_bloc_state.dart  (+ canAutoSolve on GameInProgress)
              bloc/game_bloc.dart        (solve-on-emit, cascade handler, guard)
ui/           top_bar.dart               (+ solve button)
```

`core/` gains no Flutter import. The bloc remains the only thing that
mutates `core/` state; widgets still only dispatch events.

## Component 1 — `core/solver.dart`

A single free function. It is a plain function, not a method on `GameRules`,
because it is entirely generic — it only needs the existing interface plus
the new `advanceStock` hook.

```dart
/// Greedily auto-finishes [state] under [rules]: repeatedly send any card
/// whose top is a legal foundation move to that foundation, cycling the
/// stock (via [GameRules.advanceStock]) when nothing else is playable, until
/// the game is won or progress stalls. Returns the ordered list of moves
/// that wins, or null if the board cannot be trivially finished this way.
///
/// Operates on a clone; [state] is not mutated. The returned moves, applied
/// in order to a board equal to [state], reproduce the winning trajectory.
List<Move>? solveGreedy(GameState state, GameRules rules);
```

**Algorithm** (on `state.copy()`):

1. If `rules.isWon(clone)` → return the collected moves.
2. Look for a foundation move: for each pile index `p`, take its top card and
   ask `rules.autoTargets(clone, p)` filtered to targets whose pile
   `kind == PileKind.foundation`. On the first hit, build the single-card
   `Move`, `applyMove` it to the clone, append it to the result, reset the
   stall counter, and loop.
3. If no foundation move exists, ask `rules.advanceStock(clone)`.
   - `null` → the board is stuck. Return `null`.
   - otherwise → `applyMove` it, append, increment the stall counter, loop.
4. **Termination guard:** track cycles since the last foundation move. If
   that count exceeds `stock.length + waste.length + 1` (a full pass over the
   remaining deck with no card becoming playable), return `null`. A hard
   overall iteration cap (e.g. a few hundred) is a secondary safety net
   against logic errors.

Foundation moves in these variants are always single top cards, so
`autoTargets` with the default `cardIndex` (top card) is the right query;
Klondike's waste top is covered because `isLegalMove` does not restrict the
source pile kind. Klondike tableau→foundation moves that expose a face-down
card flip it via the existing `_applyMove` logic, so the solver naturally
progresses through boards that still have face-down cards, as long as they
unfold under foundation-plus-cycle play.

## Component 2 — `GameRules.advanceStock`

```dart
/// A system move that cycles the stock to expose new cards (a draw, or a
/// recycle once the stock is exhausted), or null for variants with no stock
/// or nothing left to cycle. Apply with [GameState.applyMove].
Move? advanceStock(GameState state);
```

- **Klondike:** `buildDraw(state) ?? buildRecycle(state)` — reuses the
  existing builders verbatim.
- **FreeCell:** `return null;`.

Both variants use `implements GameRules`, so this addition forces every
current and future variant to declare its stock behaviour explicitly —
consistent with the project rule that variant-specific knowledge lives
behind the `GameRules` seam, never in a solver or a widget.

## Component 3 — Bloc

**Detection.** After every board change the bloc computes
`solveGreedy(_state, rules)` and caches it in a private `List<Move>?
_solution`. The cost is a bounded pure-Dart simulation (≲ ~100 steps),
negligible per emit. `canAutoSolve == (_solution != null)`.

To avoid scattering the recompute, in-progress emissions funnel through one
helper that builds `GameInProgress` with the freshly computed flag; won
emissions skip solving (`canAutoSolve` is false on `GameWon`).

**State.** `GameInProgress` gains a `bool canAutoSolve` field (default
`false`) included in its `props` so `buildWhen` and de-duplication see it.

**Event.** New `AutoSolveRequested` (no fields).

**Cascade handler.** On `AutoSolveRequested`, if `_solution == null` it is a
no-op. Otherwise it sets a `_solving` guard and steps the cached solution:

```
for each move in solution:
  _state.applyMove(move)
  if won:  record win, clear save, emit GameWon   (then stop)
  else:    emit GameInProgress (animates this step)
  await delay(stepDuration)
```

Each `emit` of a new board triggers the existing card-move animation for
that step, producing the one-by-one cascade. The final move reaches the won
state and flows through the *existing* win path (`recordResult(won: true)` +
`clearSave`), so an auto-solved game is recorded as a normal win, with time
and move count accrued through the cascade — matching the product decision.

`stepDuration` is a constructor-injectable `Duration` (default ~120 ms) so
tests inject `Duration.zero` for deterministic, instant runs.

**Input guard.** While `_solving` is true, the player-input handlers
(`MoveRequested`, `TapMoveRequested`, `DoubleTapRequested`, `UndoRequested`,
`RedoRequested`) early-return, so nothing interleaves with the cascade. The
`Tick` timer keeps running (time counts through the cascade, per the win
decision).

Replaying the cached moves on the real board is safe: input is blocked
during the cascade, so the real state matches the clone at each step, and
each `Move` carries its own cards and flip flags deterministically.

## Component 4 — UI

`TopBar` gains a gold `IconButton` (`Icons.auto_fix_high`, the ✨ wand,
`color: GamePalette.gold`, tooltip "Solve") rendered immediately before the
undo/redo pair, present only when the current state is `GameInProgress` with
`canAutoSolve == true`, dispatching `const AutoSolveRequested()`. The
enclosing `BlocBuilder`'s `buildWhen` extends to also fire when
`canAutoSolve` changes. No new colors, fonts, or ad-hoc styles — it reuses
existing tokens and matches the undo/redo buttons.

## Latch vs. reactive

`canAutoSolve` is recomputed each state, not latched. In practice this
behaves like a sticky button — once a board is greedy-solvable, ordinary
manual moves keep it solvable — but it is always truthful: the button shows
only when pressing it will actually finish the game, never a stale button
that would half-solve.

## Testing (TDD: RED → GREEN → REFACTOR)

**Core (unit, headless, fast) — `test/unit/`**
- `solveGreedy` on a hand-built solvable Klondike endgame (ordered runs,
  stock empty) returns moves; applying them in order reaches `isWon`.
- `solveGreedy` on a Klondike board that requires cycling the stock to reach
  buried cards solves.
- `solveGreedy` on a mid-game / genuinely stuck board returns `null`.
- `solveGreedy` on a FreeCell endgame with all cards in the tableau solves.
- `solveGreedy` on a FreeCell board that is auto-finishable but still has
  cards parked in free cells solves (proves greedy beats a structural rule).
- `solveGreedy` does not mutate the input `GameState` (compare before/after).
- `advanceStock`: Klondike returns draws then a recycle; FreeCell returns
  `null`.

**Bloc (unit) — `test/unit/`**
- Emitted `GameInProgress.canAutoSolve` is `false` before and `true` exactly
  at the solvable board.
- `AutoSolveRequested` on a solvable board (zero-delay injection) drives to
  `GameWon`, calls `recordResult(won: true, …)`, and clears the save.
- `AutoSolveRequested` on a non-solvable board is a no-op.
- Player-input events dispatched during the cascade are ignored.

**Widget (happy path) — `test/widget/`**
- The solve button is absent when not solvable and present when solvable.
- Tapping the solve button drives the board to the win HUD / records
  navigation.

## Risks & mitigations

- **Infinite stock cycling** — bounded by the stall counter (full-pass
  detection) plus a hard iteration cap.
- **Cached-solution drift** — eliminated by the `_solving` input guard: no
  other mutation occurs between computing and replaying the solution.
- **Per-device animation glitches** — none introduced; the cascade reuses
  the existing, geometry-driven card-move animation, and honors reduce-motion
  exactly as manual moves already do.

## Pre-commit checklist (per CLAUDE.md)

- [ ] Tests written first, drove the change (RED → GREEN → REFACTOR).
- [ ] `flutter analyze` and `flutter test` pass; `dart format` clean.
- [ ] `core/` and `persistence/` still have zero `package:flutter` imports.
- [ ] No rules leaked into widgets; `advanceStock` keeps stock knowledge
      behind `GameRules`; the solver depends only on the interface.
- [ ] New happy-path interaction (the solve button) has a widget test.
