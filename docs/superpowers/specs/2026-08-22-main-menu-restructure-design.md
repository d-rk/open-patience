# Main menu restructure — design

**Date:** 2026-08-22
**Status:** Approved (brainstorm) — ready for implementation planning

## Summary

Restructure the main menu from a flat, one-card-per-variant list into a
two-level navigation flow, surface in-progress games for quick resume, keep the
menu from stretching on tablets, and add two param-only FreeCell variants.

Today the "variant" is the atomic unit: `klondike-draw1`, `klondike-draw3` and
`freecell` are flat ids that both select `GameRules` *and* key records
(`stats:<variant>`) and saves (`save:<variant>`). The `MainMenuScreen` renders
one card per variant id, each with New game / Resume / Records.

This change introduces a **game → variants** grouping above the existing variant
ids, without changing the meaning of a variant id or the records schema.

## Goals

1. Title screen lists **games** (Klondike, FreeCell), not variants.
2. Any **in-progress deal is visible on the title screen** and resumable in one
   tap. Multiple in-progress deals can exist at once — list them all.
3. Selecting a game opens a **per-game options page** listing that game's
   variants, each with Play / Resume (when saved) / Records.
4. The menu stays a **centered, max-width column** so it does not get too wide on
   tablets.
5. **Records** remain per variant/option (already true) and are reachable per
   variant from the options page. No records-schema change.
6. Add two param-only FreeCell variants: **2 cells (hard)** and
   **6 cells (relaxed)**.

## Non-goals (deferred — each a small independent follow-up)

- Klondike redeal limit (needs a persisted pass counter — out of scope here).
- Baker's Game / Eight Off (build-by-suit — a new `lib/core/games/` rules file).
- Recording losses (today only wins call `recordResult`).
- Responsive multi-column grid on tablet (chose the centered column instead).

## Architecture decisions

### Discrete, curated variant list (not structured option pickers)

Each game exposes a **flat list of named variants**; each list entry is exactly
one variant id and one records bucket. This matches how most solitaire apps
present options, avoids a combinatorial records blow-up, needs no toggle UI, and
fits the existing `klondike-draw1` / `klondike-draw3` ids with zero migration.
Records are keyed by variant id in any model, so the picker style does not affect
records; the set of *offered* variants is curated by hand.

### Variant catalog

Final catalog:

- **Klondike** → `klondike-draw1` (Draw 1), `klondike-draw3` (Draw 3)
- **FreeCell** → `freecell` (Classic · 4 cells, **id unchanged**),
  `freecell-cells2` (2 cells · hard), `freecell-cells6` (6 cells · relaxed)

### Layering

- **Structure** (which variant ids belong to which game) is game-domain data and
  lives in **`lib/core/`**, Flutter-free.
- **Labels** (human-readable game titles, variant short labels, descriptors)
  stay in **`lib/ui/`** (`variant_labels.dart`).
- Persistence gains one method behind the existing `RecordsRepository`
  interface; no schema change.

## Detailed design

### Core — `lib/core/game_catalog.dart` (new, pure Dart)

```dart
class Game {
  const Game({required this.id, required this.variantIds});
  final String id;               // stable game id, e.g. 'klondike'
  final List<String> variantIds; // ordered variant ids in this game
}

class GameCatalog {
  static const List<Game> games = <Game>[ /* klondike, freecell */ ];
  static Game gameForVariant(String variantId); // throws on unknown
}
```

- `games` is ordered for menu display.
- Every `variantId` listed must resolve in `GameRegistry.rulesFor`, and every
  `GameRegistry.ids` entry must appear in exactly one game (drift guard test).
- `gameForVariant` lets the title screen map a `SavedGame.variant` back to its
  game for labelling.

### Core — `GameRegistry`

- Add constants `freecellCells2 = 'freecell-cells2'`,
  `freecellCells6 = 'freecell-cells6'`.
- Extend `ids` with the two new ids.
- Extend `rulesFor` to map them to `FreecellRules(freecellCount: 2 | 6)`.

### Core — `FreecellRules`

- Add `FreecellRules({int freecellCount = 4})` with
  `assert(freecellCount >= 1 && freecellCount <= 8)` (guard clause / assert for
  supported range; the two shipped variants are 2 and 6).
- Derive layout offsets from the count:
  `firstFreecell = 0`, `firstFoundation = freecellCount`,
  `firstTableau = freecellCount + foundationCount`. Tableau count stays 8.
- `maxMovable` already reads the free-cell count; make it count from
  `freecellCount` rather than the hardcoded `4`.
- `id => freecellCount == 4 ? 'freecell' : 'freecell-cells$freecellCount'` so
  Classic keeps its existing id (no records/save migration).
- No presentation change: `board.dart` lays out piles by iterating and switching
  on `PileKind`, so a different free-cell count renders automatically.

### Persistence — `RecordsRepository` + shared-prefs impl

Add one method:

```dart
/// All in-progress saves, newest-first is not required (menu sorts/labels).
Future<List<SavedGame>> loadAllSaves();
```

`SharedPrefsRecordsRepository.loadAllSaves` enumerates `_prefs.getKeys()`,
selects those starting with `savePrefix`, decodes each blob, and skips corrupt
or unparseable entries (same defensive degrade-to-clean behaviour as
`loadGame`). No change to `Stats`, `recordResult`, `statsFor`, or the JSON
schema.

### UI — screens

**`MainMenuScreen` (rewritten body)**
- Keeps `MenuBanner`, `GameWordmark`, `GameSignature`.
- New **Continue playing** section: `FutureBuilder<List<SavedGame>>` over
  `loadAllSaves()`. For each save, a row showing the game·variant label
  (`gameForVariant` + `variantTitle`), elapsed·moves (from `SavedGame.state`),
  and a **Resume** control that opens the board via a `GameBloc` seeded from the
  save (same construction as today's `_resume`). Section hidden when the list is
  empty.
- **Games list**: one row per `GameCatalog.games` entry, tapping pushes
  `GameOptionsScreen` for that game.
- Body wrapped in the shared centered max-width column (see below).

**`GameOptionsScreen` (new, `lib/ui/game_options_screen.dart`)**
- `FeltHeader(title: <game title>, onBack: pop)`.
- One row per `game.variantIds`: variant short label + descriptor, and
  **Play** (new random-seed deal → `GameBloc.newGame` → `GameScreen`),
  **Resume** (only when `hasSave(variantId)` → load + resume), **Records ›**
  (pushes `RecordsScreen` for that variant). This is the per-variant New
  game/Resume/Records logic that lives in `MainMenuScreen` today, moved here.
- Body wrapped in the shared centered max-width column.

**Shared tablet-width wrapper**
- A small reusable widget (e.g. `MenuWidthLimit` in `lib/ui/theme/widgets.dart`)
  that centers its child and caps width (~`520`). Applied to the title body and
  the options body. Felt fills the margins.

**`RecordsScreen`** — unchanged (already takes `variant` + `title`).

### UI — labels (`lib/ui/variant_labels.dart`)

- Keep `variantTitle(id)`; add labels for `freecell-cells2` / `freecell-cells6`.
- Add `gameTitle(String gameId)` (Klondike, FreeCell) and short per-variant
  labels + one-line descriptors used by the options rows and Continue section.

## Data flow

- Title → tap game → `GameOptionsScreen`.
- Options → Play → new `GameBloc` → `GameScreen`.
- Options → Resume / Title Continue → Resume → `GameBloc` from `SavedGame` →
  `GameScreen`.
- Options → Records → `RecordsScreen(variant)`.

Direction is unchanged: widgets construct a `GameBloc` and push a screen; no game
logic enters the menu widgets.

## Error handling / edge cases

- `loadAllSaves` skips corrupt blobs; a bad save never blocks the menu.
- A save whose variant id is no longer known (future removal) is skipped when
  labelling (guard in `gameForVariant` callers).
- Empty Continue section when no saves.
- FreeCell 2-cell deals may be unsolvable for some seeds — acceptable; the
  auto-completable property test keeps using solvable setups.

## Testing strategy (TDD: RED → GREEN → REFACTOR)

**Core (unit)**
- `FreecellRules(freecellCount: 2 | 6)`: deal produces `count` free cells + 4
  foundations + 8 tableau; correct total cards dealt; `id` string; `maxMovable`
  reflects the count; a move into a free cell still caps at one card; win check.
- `GameCatalog`: games/order, `variantIds` per game, `gameForVariant`
  round-trips, and a drift guard (catalog ⇄ `GameRegistry.ids` cover the same
  set).
- Existing Klondike/FreeCell tests stay green; `toJson`→`fromJson` round-trip for
  the new variants.

**Persistence (unit)**
- `loadAllSaves`: returns all saves; empty when none; skips a corrupt blob; a
  saved game round-trips (variant/seed/state).

**Presentation (widget)**
- Title renders the games list; Continue section appears when a save exists with
  a working Resume→board and is absent when none.
- Tap a game → options screen.
- Options: rows for each variant; Play → new board; Resume shown only when a save
  exists and resumes; Records → records screen.
- Menu body is width-constrained on a wide (tablet) surface.
- Rewrite the existing `MainMenuScreen` widget tests for the new structure.

## Files touched

- **New:** `lib/core/game_catalog.dart`, `lib/ui/game_options_screen.dart`,
  tests for each.
- **Changed:** `lib/core/game_registry.dart`, `lib/core/games/freecell.dart`,
  `lib/persistence/records_repository.dart`,
  `lib/persistence/shared_prefs_records_repository.dart`,
  `lib/ui/main_menu_screen.dart`, `lib/ui/variant_labels.dart`,
  `lib/ui/theme/widgets.dart`, and affected tests.

## Pre-commit checklist (per CLAUDE.md)

- TDD drove each change (RED → GREEN → REFACTOR).
- `flutter analyze` + `flutter test` green; `dart format` clean.
- Explicit static types on public APIs.
- No game logic in widgets; `lib/core/` + `lib/persistence/` stay Flutter-free
  (the import-boundary grep check passes — `game_catalog.dart` imports no
  Flutter).
- New variants are param-only on the existing `FreecellRules`; no new rules file
  needed.
- New happy-path interactions have widget tests.
