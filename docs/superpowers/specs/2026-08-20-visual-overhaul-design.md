# In-Game & App-Wide Visual Overhaul — Design

Date: 2026-08-20

## Goal

Rework the app's presentation into a cohesive, playful game aesthetic —
"a game, not an enterprise app" — and establish a single design system so
future features stay consistent.

Three drivers:

1. **Reclaim play-screen space.** The `AppBar` title bar during play wastes
   vertical space. Remove it; move the timer/move stats to the bottom; add a
   menu button that opens a dialog for the less-frequent actions.
2. **Make it look like a game.** Emerald-felt table, cream playing cards,
   gold accents, rounded playful shapes — applied consistently across the
   play screen, main menu, and records screen.
3. **Keep it consistent going forward.** One theme + shared widgets that all
   screens compose from, documented as a rule in `CLAUDE.md`.

This is a presentation-only change. `lib/core/` and `lib/persistence/` are
untouched and remain Flutter-free.

## Chosen design (validated via visual mockups)

- **Direction:** *Emerald Felt* — radial green felt gradient background, gold
  (`#F6C65B`) accents, cream (`#FFF8EC`) cards.
- **Cards:** *Classic Crisp* — cream face, two-color deck (red `#C0392B` /
  ink `#1C2833`), rank-over-suit index top-left and mirrored bottom-right, a
  faint large center pip, rounded corners, subtle shadow. Face-down back is an
  emerald-and-gold stripe with a gold border.
- **Menu dialog:** *Icon tiles* — cream card, gold border, green title banner
  showing the variant name and live `mm:ss · N moves`. Restart (green tile)
  and Shuffle (amber tile) side by side; Exit to menu (red full-width bar).

## Architecture

Dependency direction is unchanged. All new code lives in `lib/ui/` and
`lib/presentation/`; nothing new is imported by `core/` or `persistence/`.

### New design-system subsystem: `lib/ui/theme/`

Single source of truth for look-and-feel. Three files:

- **`game_palette.dart`** — pure design tokens as `const` values, plus the
  `formatDuration(int seconds) -> 'mm:ss'` helper (relocated from `Hud`).
  Tokens (names indicative):
  - `feltGradient` (radial green), `feltGreenDark`, `feltGreenLight`
  - `gold`, `cardFace` (cream), `cardRed`, `cardInk`
  - `pileSlotOutline` (gold-tinted)
  - menu action colors: `actionRestartBg`, `actionShuffleBg`, `actionExitBg`
    and their foregrounds
  No widget outside `theme/` hardcodes `Color(0x…)`.
- **`app_theme.dart`** — `AppTheme.themeData` returning a `ThemeData` wired
  into the root `MaterialApp` in `main.dart`. A `ColorScheme` seeded from the
  emerald/gold palette; rounded `cardTheme`, `dialogTheme`,
  `filledButtonTheme`, `outlinedButtonTheme`, `textButtonTheme`; playful
  `textTheme`. This is the primary consistency mechanism: standard Material
  widgets in future features inherit the look with no extra styling.
- **`widgets.dart`** — small reusable presentational widgets the screens
  compose from:
  - `FeltBackground` — a `Container`/`DecoratedBox` painting the felt gradient;
    wraps a screen body.
  - `FeltHeader` — gold title text with an optional leading back button
    (replaces `AppBar` on themed screens).
  - `GamePill` — the rounded stat pill (icon + label) used by the stat bar and
    reusable elsewhere.
  - `GameActionTile` — a menu action tile (icon + label + background color),
    used for Restart/Shuffle/Exit.

### Play screen: `lib/ui/game_screen.dart`

- Remove the `Scaffold.appBar`.
- Body inside `SafeArea` becomes a `Column`:
  1. **`TopBar`** (new widget, see below) — ☰ menu button left, undo/redo right.
  2. **`Board`** in an `Expanded`, wrapped by the existing win `BlocListener`,
     over a `FeltBackground`.
  3. **`StatBar`** (new widget) — centered `GamePill`s for timer and moves.
- `Scaffold.backgroundColor` uses the felt token (or the whole body is wrapped
  in `FeltBackground`).
- The ☰ button opens the menu dialog via `showGameMenu(context, bloc)`.

### HUD split: retire `lib/ui/hud.dart`

The current `Hud` mixes stats and all four action buttons. Split its
responsibilities:

- **`TopBar`** (`lib/ui/`, game-screen chrome) — menu button + Undo + Redo.
  Undo/Redo keep their exact `tooltip: 'Undo'` / `'Redo'` and enablement logic
  (`canUndo`/`canRedo`), with a scoped `buildWhen`.
- **`StatBar`** (`lib/ui/`) — timer + moves as `GamePill`s. Preserves the exact display
  strings `'mm:ss'` (via `formatDuration`) and `'$moveCount moves'`, with a
  scoped `buildWhen`.

`Hud.formatDuration` moves to `game_palette.dart` as a top-level
`formatDuration`. `records_screen.dart`'s reference is updated accordingly.
The `Hud` class is removed once both consumers (game screen, records screen)
no longer need it. Restart and New-deal buttons are removed from the play area
entirely — they now live only in the menu dialog.

### Menu dialog: `lib/ui/game_menu.dart`

`Future<void> showGameMenu(BuildContext context, GameBloc bloc)` shows a
themed dialog (cream card, gold border, green banner). Banner shows
`variantTitle(bloc.variant)` and live `mm:ss · N moves` from the current
state. Three `GameActionTile`s:

- **Restart** → close dialog, dispatch `RestartDealRequested()`.
- **Shuffle** → close dialog, dispatch `NewDealRequested()` (fresh random deal).
- **Exit to menu** → close dialog, `Navigator.pop` the play route back to the
  main menu.

Each action closes the dialog first, then acts.

### Cards: `lib/presentation/card_view.dart`

Restyle `CardFace` only (no change to `CardView`'s gesture/drag wiring or the
`_DragFeedback` structure):

- Face-up: cream face, palette red/ink, rank-over-suit index top-left **and**
  mirrored bottom-right, faint large center pip, rounded corners, subtle
  shadow. Colors from `game_palette.dart`.
- Face-down: emerald/gold striped back with gold border.
- `Semantics` labels (`_semanticLabel`) are unchanged so existing finders and
  screen readers keep working.

### Piles: `lib/presentation/pile_view.dart`

`_placeholder()` empty-slot outline restyled to the gold-tinted
`pileSlotOutline` token. No structural/logic change.

### Main menu: `lib/ui/main_menu_screen.dart`

- Replace `AppBar` with `FeltHeader` (gold `♠ Solitaire ♥`-style title) over a
  `FeltBackground`.
- Each `_VariantCard` becomes a cream rounded card; buttons keep their labels
  (`New game`, `Resume`, `Records`) and actions but pick up the themed button
  styles (green filled / amber / outlined). No navigation logic changes.

### Records: `lib/ui/records_screen.dart`

- Replace `AppBar` with `FeltHeader` (title + gold back button) over a
  `FeltBackground`.
- `_RecordTile` becomes a cream rounded row with the value in a green/red
  accent. Labels and values unchanged (`Games played`, `Games won`,
  `Win rate`, `Best time`, `Fewest moves`, `Current streak`, `Longest
  streak`).
- Update the `formatDuration` reference from `Hud.formatDuration` to the new
  top-level helper in `game_palette.dart`.

### Root: `lib/main.dart`

Wire `AppTheme.themeData` into the root `MaterialApp` so the theme applies
app-wide.

## Data flow

Unchanged. Widgets still dispatch `GameEvent`s to `GameBloc`; the menu dialog
dispatches the same existing events (`RestartDealRequested`,
`NewDealRequested`) it replaces buttons for; Exit uses `Navigator`. No new
events, no rules in widgets.

## Error handling / edge cases

- Menu dialog uses the dialog's own context correctly for pop vs. route pop
  (dismiss the dialog, then pop the play route for Exit).
- Undo/Redo remain disabled (`onPressed: null`) when `!canUndo` / `!canRedo`.
- Card restyle must not change hit-test/drag geometry (same `size`-based
  layout) so drag-and-drop and tap targets are unaffected.

## Testing (TDD)

Preserve the contract the existing widget suite depends on: the strings
`'$n moves'` and `'mm:ss'`, the `Undo`/`Redo` tooltips, and card `Semantics`
labels. Most of `test/widget/game_widget_test.dart` should pass unchanged;
adjust only where it structurally assumed the old single `Hud` row.

New/updated tests (RED → GREEN → REFACTOR):

- **Menu opens:** tapping the ☰ button shows the dialog and the variant title.
- **Restart:** tapping the Restart tile dispatches `RestartDealRequested`
  (deal restored to its initial state; dialog closed).
- **Shuffle:** tapping the Shuffle tile dispatches `NewDealRequested` (new
  deal; dialog closed).
- **Exit:** tapping Exit closes the dialog and pops back to the main menu.
- **Stats at bottom / top bar:** timer + moves still render (strings intact);
  undo/redo still work from the top bar (existing undo/redo test adapted).
- **`formatDuration`:** a direct unit test for the relocated helper.

Card, pile, main-menu, and records restyles are visual; they're covered by the
existing finders continuing to pass — no new logic tests, per the project's
"don't test framework/paint" stance.

Gates: `flutter analyze` clean, `flutter test` green, `dart format` no diffs,
and the core/persistence "no Flutter imports" boundary still holds.

## Consistency guard

- New **"Design language"** section in `CLAUDE.md`: this is a game, not an
  enterprise app — playful, colorful, rounded. All colors and shapes come from
  `lib/ui/theme/`; widgets never hardcode `Color(0x…)` or ad-hoc style colors;
  new screens compose from the shared `widgets.dart` pieces and inherit
  `AppTheme`. (Documented rule only — no CI check this pass.)

## Out of scope

- Move / deal / win animations (planned follow-up).
- Any change to game rules, persistence, or the records data model.
- A CI grep guard for hardcoded colors (deferred; rule is documented only).
