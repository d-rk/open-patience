# Design: signature footer on the main menu

Date: 2026-08-21
Status: approved

## Goal

Add a small, handwritten "a game by Dirk Wilden" signature footer, pinned to
the bottom of the main menu, styled as dark ink pressed into the felt.

## Look and feel

Decided interactively (visual companion):

- **Font:** Satisfy — a brushy, classy handwriting/script face.
- **Colour:** dark ink, black at **44%** opacity (subtle, low-contrast
  against the green felt).
- **Emboss:** a single faint highlight shadow — white at ~**10%** opacity,
  offset `(0, 1)` — giving a "pressed into the felt" look.
- **Size:** ~20 logical pixels.
- **Alignment:** horizontally centred.
- **Placement:** pinned at the very bottom of the screen (always visible),
  below the scrolling variant list.
- **Wording:** exactly `a game by Dirk Wilden` (lowercase leading "a").

## Font asset (offline, F-Droid-safe)

Satisfy (by Font Diner) is an **Apache-2.0** font from Google Fonts,
AGPL-compatible. Bundle it locally like the existing faces — never fetched at
runtime:

- `assets/fonts/Satisfy-Regular.ttf`
- `assets/fonts/LICENSE-Satisfy.txt` (Apache-2.0 license, alongside the asset)
- `pubspec.yaml`: new `family: Satisfy` entry under `fonts:`.
- `lib/ui/theme/game_fonts.dart`: new token
  `static const String signature = 'Satisfy';`.

## Colour tokens

Widgets never hardcode `Color(0x…)`; add tokens in
`lib/ui/theme/game_palette.dart`:

- `signatureInk` — black at 44% opacity (the ink).
- `signatureEmboss` — white at ~10% opacity (the emboss highlight).

## Widget

New shared widget in `lib/ui/theme/widgets.dart`:

- `GameSignature` — a `const` `StatelessWidget` rendering a centred
  `Text('a game by Dirk Wilden')` with:
  - `fontFamily: GameFonts.signature`
  - `color: GamePalette.signatureInk`
  - `fontSize: 20`
  - `shadows: [Shadow(offset: Offset(0, 1), color: GamePalette.signatureEmboss)]`
  - small vertical padding (e.g. `EdgeInsets.only(bottom: 12, top: 4)`).

## Placement

In `lib/ui/main_menu_screen.dart`, append `const GameSignature()` as the last
child of the top-level `Column` (after the `Expanded` list), inside
`SafeArea`, so it is pinned at the bottom of the screen on every device.

## Testing (TDD)

- **RED → GREEN** `test/widget/theme_widgets_test.dart`: `GameSignature`
  renders the exact string `a game by Dirk Wilden` and its `Text` uses
  `GameFonts.signature` as the font family.
- **RED → GREEN** `test/widget/main_menu_test.dart`: the main menu shows the
  text `a game by Dirk Wilden`.

## Scope guard / non-goals

- Pure presentation. No changes to `lib/core/` or `lib/persistence/`; no game
  logic touched. The core/persistence "no Flutter imports" boundary is
  unaffected.
- No animation, no theming toggle, no configurability — one font, one colour
  pair, one widget, one line added to the menu.

## Licensing

Satisfy ships under the Apache License 2.0, which is one-way compatible with
the project's AGPL-3.0-only licensing. The `LICENSE-Satisfy.txt` file is
bundled alongside the `.ttf` in `assets/fonts/`.
