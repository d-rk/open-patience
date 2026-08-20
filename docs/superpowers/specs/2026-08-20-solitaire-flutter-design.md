# Solitaire (Flutter) — v1 Design

**Date:** 2026-08-20
**Status:** Approved design, pre-implementation
**Framework:** Flutter (latest stable)
**Language:** Dart

## Purpose

Build a cross-platform (mobile/tablet) solitaire game as a vehicle for
practicing clean architecture and test-first development. The engineering
discipline — a hard-separated pure logic layer, reproducible deterministic
deals, and a fast headless test suite — is as much the point of the project
as the game itself.

The game must be **easily extensible** to new solitaire variants and have
**testability built in from the start**.

## v1 Scope

**Games**
- Klondike (draw-1 and draw-3)
- FreeCell
- A variant registry so a third game is a new logic file, not a widget change.

**Play**
- Drag-and-drop of single cards and valid multi-card stacks
- Tap-to-move: tap a card to send it to its only legal destination
- Double-tap: send a card to its foundation if legal
- Full undo / redo

**HUD**
- Elapsed timer (counts up during play)
- Move counter

**Records (local)**
- Per-variant: best time, fewest moves, games played, games won, win %,
  current streak, longest streak
- A records/leaderboard screen showing these per variant
- Local storage only in v1, behind a repository interface so an online
  backend can be added later without touching game logic

**Persistence**
- Save & resume an in-progress game across app close
- Restart the same deal (replay the same seed)
- Deterministic seeded deals (reproducible / shareable)

**Quality**
- Fast headless `flutter test` unit suite for logic, persistence, and Bloc
- Widget tests covering every happy-path interaction flow
- A small `integration_test` suite exercising the golden path on a real
  device/emulator
- GitHub Actions CI running unit + widget tests on every push, from the
  first commit

**Explicitly deferred to v2+**
- Online / global leaderboard
- Hints and legal-move highlighting
- Solvable-only deals
- Themes / card backs / skins
- Sound and haptics
- Klondike scoring (Standard / Vegas)
- Achievements
- Cloud sync

## Architecture

Strict dependency direction — arrows point one way only:

```
ui/, presentation/  ─▶  core/, persistence/
```

`core/` and `persistence/` are pure Dart: **zero `package:flutter`
imports**. Since this is a single Flutter app rather than a multi-package
workspace, that boundary is enforced by a CI grep check (see Testing & CI)
rather than by the package system physically preventing the import.

### `core/` — pure logic (no Flutter, no widgets)

Fully unit-testable with plain `flutter test`, no widget pumping.
Instantiate a whole game and play thousands of moves in a loop in
milliseconds.

- `card.dart` — value data: suit, rank, faceUp
- `deck.dart` — builds a standard 52-card deck; seeded shuffle via an
  **injected `Random`** (`dart:math`'s `Random(seed)` — no global
  randomness, no extra package needed)
- `pile.dart` — an ordered collection of cards plus a pile *kind*
  (stock / waste / foundation / tableau / freecell)
- `move.dart` — a value object describing a move: from-pile, cards, to-pile.
  The unit of undo/redo.
- `game_state.dart` — holds all piles; applies and reverts moves; maintains
  undo/redo stacks; win check; tracks elapsed time and move count as part
  of state; **`toJson`/`fromJson`** for save-resume. Game-agnostic: knows
  nothing about which variant is being played. Implements value equality
  (via `equatable`) so undo tests can assert an exact prior snapshot.
- `game_rules.dart` — abstract interface implemented per variant:
  - `deal(deck) -> List<Pile>`
  - `isLegalMove(from, cards, to) -> bool`
  - `isWon(state) -> bool`
  - `autoTargets(state, card)` — legal destinations, used by tap-to-move
    and double-tap-to-foundation
  - `maxMovable(state)` — e.g. FreeCell free-cell/empty-column math
- `games/klondike.dart`, `games/freecell.dart` — implement `GameRules`
- `game_registry.dart` — maps a variant id (e.g. `"freecell"`) to its rules

Tap-to-move and double-tap add **no new logic** to the view; they resolve
destinations through `GameRules.autoTargets`.

### `persistence/` — local storage behind an interface

- `records_repository.dart` — abstract interface (record a result, read
  stats per variant, load/save current game). This interface is the seam
  an online backend slots into later.
- `shared_prefs_records_repository.dart` — concrete implementation backed
  by `shared_preferences`, storing JSON-encoded blobs under fixed keys.
- `stats.dart` — value object: games played/won, win %, best time, fewest
  moves, current/longest streak, per variant.

Stored data:
- Current-game save: variant id + seed + JSON-serialized `GameState`,
  under key `save:<variant>`
- Stats table: one JSON blob per variant under key `stats:<variant>`

### State glue — `presentation/bloc/`

A `GameBloc` (`flutter_bloc`) is the state-management seam that connects
widget-tree intents to the pure `core/` API and re-exposes `GameState` as
UI-facing state.

- `game_event.dart` — `MoveRequested`, `TapMoveRequested`,
  `DoubleTapRequested`, `UndoRequested`, `RedoRequested`,
  `NewDealRequested`, `SaveRequested`
- `game_bloc_state.dart` — `GameInProgress(GameState)`,
  `GameWon(GameState, elapsed, moves)`
- `game_bloc.dart` — on each event, delegates to `GameState.tryMove()` /
  `GameRules`; **holds no rules of its own**. On a win, calls
  `RecordsRepository.recordResult(...)`.

### `presentation/` — dumb widgets that render state and forward input

- `board.dart` — lays out piles responsively for phone and tablet aspect
  ratios
- `card_view.dart` — card rendering + `Draggable`/`DragTarget` and tap
  handling (all built into Flutter, no extra package)
- `pile_view.dart` — renders a pile

Widgets rebuild via `BlocBuilder`/`BlocListener` on `GameBloc` state
changes and animate with Flutter's built-in implicit animations
(`AnimatedPositioned`, `AnimatedContainer`). On a drop or tap they
dispatch a `GameEvent`. Widgets contain no rules.

### `ui/`

- `main_menu_screen.dart` — pick a variant; offer Resume if a save exists
- `hud.dart` — timer, move counter, undo, redo, restart deal, new deal
- `records_screen.dart` — per-variant leaderboard / stats

## Data Flow

One direction, easy to reason about:

1. Input (drag drop or tap) → widget dispatches a `GameEvent`
   (`MoveRequested`, etc.)
2. `GameBloc` calls `GameState.tryMove(move)` → asks active
   `GameRules.isLegalMove()`
3. On legal: mutate piles, push to undo stack, increment move count, emit
   new Bloc state
4. `BlocBuilder`s re-render affected views + animate
5. On win: `RecordsRepository.recordResult(variant, time, moves)` updates
   stats and best records
6. On `AppLifecycleState.paused`/`detached`: serialize current `GameState`
   to the save blob via `RecordsRepository`

## Responsive / Mobile Layout

- Single Flutter app targeting Android and iOS (App Store / Play Store)
- Portrait-first responsive layout using `LayoutBuilder`/`MediaQuery` to
  scale pile spacing and card size across phone and tablet aspect ratios
- Touch drag maps directly to card movement via `Draggable`/`DragTarget`;
  tap-to-move as the primary low-effort interaction

## Testing Strategy

The test pyramid is weighted toward the pure logic layer, which is where
correctness lives and where headless tests run in milliseconds — same
principle as the original design, translated to Flutter's test tooling.

**Logic tests (the bulk, headless, `flutter test test/unit/`)**
- Deal fixed seeds; assert legal moves accepted and illegal moves rejected
- Undo restores an exact prior snapshot (state equality via `equatable`)
- Win detection for each variant
- Round-trip: `toJson` → `fromJson` yields an equal `GameState`
  (protects save/resume)
- Records math: win %, streak transitions, best-time / fewest-moves updates
- Property-style test: loop over many seeds, auto-complete each game,
  assert it reaches the won state (no dedicated property-testing package —
  a seeded loop keeps dependencies minimal)

**Bloc tests (`bloc_test`)**
- For each `GameEvent`, assert the exact sequence of emitted
  `GameBlocState`s

**Persistence tests**
- Run against `SharedPreferences.setMockInitialValues()` — no real
  platform channel needed

**Presentation tests — two tiers**

Widget tests alone cannot prove the game works on a real device: they run
under `TestWidgetsFlutterBinding` with synthetic frame pumping, simulated
gestures, and no real platform channels. So presentation testing is split:

1. **Widget tests (`flutter test test/widget/`, headless, every push)** —
   one test per happy-path flow: new deal renders correctly, drag a card
   between tableau piles, tap-to-move, double-tap-to-foundation,
   undo/redo, win updates the HUD and navigates to records, save →
   simulated relaunch → resume. Cheap given the dumb-widget architecture;
   verifies gesture → correct event → correct re-render wiring.
2. **Integration tests (`integration_test` package, real device/emulator,
   less frequent)** — 1-2 true end-to-end flows (e.g. "deal → play to a
   win → see it reflected in records") launched on an actual
   device/emulator/simulator. This is the tier that exercises real touch
   input, real rendering, and real platform channels. Not written
   exhaustively — a couple of critical flows, run in a separate CI lane
   (or manually before release), not on every push.

**CI**
- GitHub Actions, `subosito/flutter-action`, runs on every push:
  1. `flutter pub get`
  2. `flutter analyze`
  3. A grep step failing the build if `lib/core/` or `lib/persistence/`
     import `package:flutter`
  4. `flutter test` (unit + widget)
- `integration_test` suite runs in a separate, less-frequent CI lane
  (emulator-backed) or as a pre-release gate, not on every push.

## Key Design Decisions

- **Seeded `Random` injected into `deal()`** — reproducible deals underpin
  both restart-same-deal and deterministic tests; no global randomness.
- **Moves are reversible value objects** — undo/redo falls out for free and
  is what makes the logic layer so testable.
- **`GameState` is game-agnostic; rules live behind one interface** — the
  extensibility hinge: a new variant is one new file implementing
  `GameRules`.
- **Records behind a repository interface** — local now, online-ready later
  without touching game logic.
- **Logic has zero Flutter imports** — the discipline that makes the core
  fully testable without widget pumping, enforced by a CI grep check since
  this is a single app rather than a multi-package workspace.
- **`flutter_bloc` as the state-management seam** — it exists solely to
  connect widget-tree intents to the pure `core/` API, and holds no rules
  itself.
- **Widget tests exhaustive, integration tests selective** — headless
  widget tests are cheap enough to cover every happy path on every push;
  real-device confidence comes from a small, deliberately limited
  `integration_test` suite rather than trying to make headless tests do
  a job they structurally can't.
- **Minimal dependency footprint** — no database, no DI framework, no
  routing package, no codegen (`freezed`/`json_serializable`) — manual
  `toJson`/`fromJson`, `shared_preferences`, `flutter_bloc` + `equatable`
  cover v1 without adding tooling overhead.

## Additional Libraries

Answering "do we need additional libraries?" directly:

| Package | Role | Notes |
|---|---|---|
| `flutter_bloc` | State management | Event→state modeling for `GameBloc` |
| `equatable` | Value equality | For Bloc states/events and `GameState` snapshot comparison (undo tests) |
| `shared_preferences` | Local persistence | Simple key-value store for the save blob + stats |
| `flutter_lints` | Linting | Standard Flutter lint rules |
| `bloc_test` (dev) | Bloc testing | Assert exact emitted-state sequences |
| `integration_test` (dev, ships with Flutter SDK) | Real-device e2e tests | Golden-path flows only |

Not needed: a database (`sqflite`/`hive` — scope is a handful of stat rows
and one save blob), a DI framework, a routing package (3 screens,
`Navigator` is enough), or codegen (`freezed`/`json_serializable` — manual
`toJson`/`fromJson` is small enough by hand and keeps `core/` dependency-free).
No package is needed for seeded randomness (`dart:math`'s `Random(seed)`)
or drag-and-drop/animation (`Draggable`/`DragTarget` and implicit
animations are built into Flutter).

## Project Layout (indicative)

```
lib/
  core/
    card.dart
    deck.dart
    pile.dart
    move.dart
    game_state.dart
    game_rules.dart
    game_registry.dart
    games/
      klondike.dart
      freecell.dart
  persistence/
    records_repository.dart
    shared_prefs_records_repository.dart
    stats.dart
  presentation/
    bloc/
      game_event.dart
      game_bloc_state.dart
      game_bloc.dart
    board.dart
    card_view.dart
    pile_view.dart
  ui/
    main_menu_screen.dart
    hud.dart
    records_screen.dart
  main.dart
test/
  unit/            # headless core + persistence + bloc tests
  widget/          # happy-path presentation tests
integration_test/
  golden_path_test.dart
.github/workflows/
  ci.yml
pubspec.yaml
```
