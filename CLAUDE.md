# CLAUDE.md

Guidance for working in this repository. Read this before writing code.

## Project

Cross-platform (mobile/tablet) solitaire game built in **Flutter** with
**Dart**. Built as a vehicle for clean, testable architecture. See
`docs/superpowers/specs/2026-08-20-solitaire-flutter-design.md` for the
full design.

## Non-negotiable rules

1. **Test-Driven Development is mandatory.** No production code is written
   before a failing test that requires it. See "TDD workflow" below.
2. **Game logic never imports Flutter.** Everything in `lib/core/` and
   `lib/persistence/` is pure Dart, with zero `package:flutter` imports.
   This is what makes the logic testable in milliseconds with no widget
   pumping, and is the core discipline of this project. Enforced by a CI
   grep check (see Commands).
3. **Rules live behind the `GameRules` interface.** A new solitaire variant
   is one new file in `lib/core/games/` — never a change to a widget.
4. **Follow the Dart/Flutter style guide** (below). Use explicit static
   types on all public APIs.

## Architecture

Strict dependency direction — arrows point one way only:

```
ui/           ─┐
                ├─▶ core        (pure Dart, no Flutter imports)
presentation/ ─┘   persistence (local storage behind an interface)
```

- `core/` — `Card`, `Deck` (seeded `Random` injected), `Pile`, `Move`
  (reversible value object = unit of undo), `GameState` (game-agnostic;
  apply/revert moves, undo/redo, win check, `toJson`/`fromJson`),
  `GameRules` interface, `games/klondike.dart`, `games/freecell.dart`,
  `game_registry.dart`.
- `persistence/` — `RecordsRepository` interface + concrete
  `SharedPrefsRecordsRepository` (writes JSON blobs via
  `shared_preferences`), `Stats`. The interface is the seam for a future
  online backend.
- `presentation/bloc/` — `GameBloc` (`flutter_bloc`): the state-management
  seam between widgets and `core/`. Delegates to `GameState`/`GameRules`;
  holds no rules of its own.
- `presentation/` — `Board`, `CardView`, `PileView`. Dumb widgets that
  render state and forward input; contain no rules. Rebuild via
  `BlocBuilder`/`BlocListener` on `GameBloc` state changes.
- `ui/` — main menu, HUD (timer/moves/undo/redo), records screen.

Data flow (one direction): input → widget dispatches a `GameEvent` →
`GameBloc` calls `GameState.tryMove()` → `GameRules.isLegalMove()` →
mutate + push undo + tick move count → emit new Bloc state → widgets
rebuild.

## TDD workflow

For every feature or fix, follow RED → GREEN → REFACTOR:

1. **RED** — write a `flutter_test` test that expresses the desired
   behavior. Run it, watch it fail for the right reason.
2. **GREEN** — write the minimum code to make it pass. Run the suite.
3. **REFACTOR** — clean up with tests green.

Never write production code without a failing test first. The bulk of
tests target `core/` and `persistence/` (fast, headless, no widget
pumping).

Must-have logic tests: legal/illegal moves per variant; `undo` restores an
exact prior snapshot; win detection; `toJson`→`fromJson` round-trip equals
original (protects save/resume); records math (win %, streaks, best-time /
fewest-moves updates); property-style test (seeded loop) that an
auto-completable game reaches won.

Presentation tests are split into two tiers — see
"Presentation testing" below. Don't skip the widget-test tier for a happy
path just because it feels like UI plumbing: that tier is what catches
gesture → event → render wiring regressions.

## Presentation testing

Widget tests (`flutter test test/widget/`) run headless under
`TestWidgetsFlutterBinding` — synthetic frame pumping, simulated gestures,
no real platform channels. They're cheap and run on every push, but they
cannot prove the app works on a real device.

- **Widget tests — every happy path, every push.** One test per
  interaction flow: new deal renders, drag a card between piles,
  tap-to-move, double-tap-to-foundation, undo/redo, win updates the HUD
  and navigates to records, save → simulated relaunch → resume.
- **`integration_test` — a couple of golden-path flows, real
  device/emulator, less frequent.** This is the tier that exercises real
  touch input, real rendering, and real platform channels. Not written
  exhaustively; run in a separate CI lane or as a pre-release gate, not on
  every push.

## Commands

```bash
# Install dependencies
flutter pub get

# Static analysis
flutter analyze

# Enforce the core/persistence "no Flutter imports" boundary
! grep -rl "package:flutter" lib/core lib/persistence

# Unit + widget suite (also what CI runs on every push)
flutter test

# Golden-path end-to-end suite (real device/emulator, run less often)
flutter test integration_test
```

Run the app locally: `flutter run`.

CI (GitHub Actions) runs `pub get` → `analyze` → the import-boundary grep
check → `flutter test` on every push and must be green before merge. The
`integration_test` suite runs in a separate, less-frequent lane (or as a
pre-release gate), not on every push.

## Dart/Flutter style

**Formatting**
- Enforced by `dart format` (2-space indent, trailing commas on
  multi-line collections/parameter lists). Run it before committing.
- Lines under 100 chars (aim for 80). One statement per line.
- Single quotes by default (Effective Dart convention); double quotes
  only to avoid escaping.

**Static typing — required here**
- Explicit types on all public APIs: `int health = 0;`,
  `void heal(int amount) { ... }`.
- `var`/type inference is fine for locals only when the type is
  unambiguous on the same line.
- Avoid `dynamic`; if a type is genuinely unknown, that's a design smell
  in this codebase.

**Naming** (Effective Dart)

| Category | Convention | Example |
|---|---|---|
| Files | snake_case | `game_state.dart` |
| Classes / Widgets | UpperCamelCase | `GameState`, `CardView` |
| Functions / variables | lowerCamelCase | `isLegalMove`, `moveCount` |
| Bloc events / states | UpperCamelCase, past/imperative | `MoveRequested`, `GameWon` |
| Constants | lowerCamelCase with `const` | `maxMovable` — **not** `MAX_MOVABLE`; Dart constants are camelCase |
| Enum names | UpperCamelCase | `PileKind` |
| Enum values | lowerCamelCase | `PileKind.foundation` |
| Private members | leading underscore | `_undoStack`, `_apply()` |

**File order:** imports → `part` directives (if any) → doc comment →
class declaration → static fields/methods → instance fields → constructor
→ getters/setters → public methods → private methods → `@override`
methods grouped with what they override. Public before private.

**Other best practices**
- Type your code — untyped/`dynamic` code catches errors too late.
- Wire Bloc events in the right direction: widgets dispatch events,
  `GameBloc` is the only thing that mutates `core/` state. Widgets never
  reach into rules directly.
- Prefer `const` constructors for widgets wherever possible — cheap
  rebuild avoidance, and the analyzer will flag missed opportunities.
- Guard clauses at the top of functions for invalid input.

## Design language

This is a **game, not an enterprise app** — the UI is playful, colorful and
rounded (the "Emerald Felt" look: green felt table, cream cards, gold
accents).

- All colors and shared shapes come from `lib/ui/theme/`:
  `game_palette.dart` (tokens + `formatDuration`), `app_theme.dart`
  (the `ThemeData` on the root `MaterialApp`), `widgets.dart`
  (`FeltBackground`, `FeltHeader`, `GamePill`, `GameActionTile`).
- Widgets never hardcode `Color(0x…)` or ad-hoc style colors — reference a
  token. New screens compose from the shared widgets and inherit `AppTheme`.
- Prefer rounded, tactile controls (stadium buttons, pill stats, tiles).
  Avoid stock enterprise-flat Material chrome (bare `AppBar` titles, plain
  list rows) on player-facing screens.

## Project layout

```
lib/
  core/            # pure Dart — zero Flutter imports
    card.dart  deck.dart  pile.dart  move.dart  game_state.dart
    game_rules.dart  game_registry.dart  games/{klondike,freecell}.dart
  persistence/     # records_repository.dart  shared_prefs_records_repository.dart  stats.dart
  presentation/    # bloc/{game_event,game_bloc_state,game_bloc}.dart
                   # board.dart  card_view.dart  pile_view.dart
  ui/              # main_menu_screen.dart  hud.dart  records_screen.dart
  main.dart
test/
  unit/            # headless core + persistence + bloc tests
  widget/          # happy-path presentation tests
integration_test/
  golden_path_test.dart
.github/workflows/ci.yml
pubspec.yaml
```

## Pre-commit checklist

- [ ] A test was written first and drove the change (RED → GREEN → REFACTOR).
- [ ] `flutter analyze` and `flutter test` both pass.
- [ ] `dart format` has been run; no formatting diffs.
- [ ] New/changed code has explicit static types and follows the style guide.
- [ ] No game logic leaked into widgets; `lib/core/` and `lib/persistence/`
      still have zero `package:flutter` imports.
- [ ] New variant (if any) is a single `lib/core/games/` file behind
      `GameRules`.
- [ ] Any new happy-path interaction has a widget test.
