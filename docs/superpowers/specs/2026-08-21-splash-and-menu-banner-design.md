# Splash Image & Animated Menu Banner — Design

Date: 2026-08-21

## Goal

Add two Blender-rendered art assets to Open Patience:

1. A **startup splash** shown when the app launches.
2. A **menu banner** shown at the top of the main menu, with a subtle
   (Flutter-driven) animation.

Both are **fully new artwork** (not derived from the existing app-icon
`.blend`), rendered as **imagery only** — the "Open Patience" wordmark stays
text drawn in Flutter with the bundled Lilita One font.

## Constraints

- **Offline / reproducible (F-Droid).** No runtime downloads; all art bundled
  as local assets. Blender scenes are the source of truth, rendered ahead of
  time.
- **Blender runs as a Flatpak** (`org.blender.Blender`). Its filesystem access
  is sandboxed: render outputs and `.blend` saves must go to project-local
  paths it can access. `/tmp` is **not** accessible from the sandbox.
- **Temporary prototype renders go to `build/art/`** (project-local,
  gitignored), never `/tmp`.
- **Palette** locked to the Emerald Felt tokens in `lib/ui/theme/game_palette.dart`:
  felt greens (`#2E8B57` / `#1C6B3C` / `#14532D`), gold `#F6C65B`, cream cards
  `#FFF8EC`, red `#C0392B`, ink `#1C2833`.
- **TDD** per `CLAUDE.md` for any Flutter widget wiring. `lib/core` and
  `lib/persistence` remain untouched (no Flutter-boundary impact).

## Art pipeline (mirrors `tools/logo/`)

Each scene is built procedurally via the Blender MCP bridge, then **saved as a
`.blend` source of truth** under `tools/art/`, with a `build_art.py` render
script analogous to `tools/logo/build_logo.py`. The `.blend` is the editable
source; the script re-renders it to PNG.

All final renders use a **transparent background** (`film_transparent = True`)
so Flutter's felt gradient shows through and the same art works on both screens.

### Phase 1 — Prototype & select

Render all **three** candidate subjects as square-ish transparent stills
(~1024²) into `build/art/` for visual selection:

- **Fanned card spread** — an arc of cream cards on felt, gold rim light, a few
  suit pips catching light.
- **Klondike tableau** — a stylized mini tableau (columns + foundation aces) at
  a dramatic low camera angle.
- **Hero ace(s)** — a single hero ace (or small floating cluster) hovering with
  soft shadows and a gold glow, lots of negative space.

Selection loop per subject: build → render to `build/art/<subject>.png` → pull
the PNG back to self-review composition/lighting/framing → adjust
camera/lights/materials → re-render until clean.

Early feasibility check: confirm the Flatpak sandbox can **write** `build/art/`
and (if a scene needs them) **read** `assets/fonts/` before committing to full
renders.

### Phase 2 — Finalize chosen subject

From the selected subject, produce two final crops and save the `.blend`
sources:

- **Splash**: centered composition, transparent PNG ~1152² →
  `assets/images/splash.png`. Source: `tools/art/splash_scene.blend`.
- **Banner**: landscape ~2:1 transparent PNG ~1600×800 →
  `assets/images/menu_banner.png`. Source: `tools/art/banner_scene.blend`.

## Flutter integration

### Splash — `flutter_native_splash`

- Add `flutter_native_splash` as a **dev dependency**.
- Config in `pubspec.yaml`:
  - `color: "#14532D"` (felt dark) as the background.
  - `image: assets/images/splash.png` (centered emblem).
  - `android_12:` centered image variant + `color` (Android 12+ splash API).
- Generate native assets with `dart run flutter_native_splash:create`.
- Fully offline; produces a true OS-level splash painted before the Flutter
  engine finishes loading.

### Menu banner — `lib/ui/widgets/menu_banner.dart`

- New `MenuBanner` widget rendering `assets/images/menu_banner.png`.
- Placed at the top of `main_menu_screen.dart`, replacing / sitting above the
  current text-only `FeltHeader` title.
- **Subtle motion, no new deps**: a slow looping `AnimationController` driving
  either a gentle vertical float (±few px) or a gold shimmer sweep (e.g.
  `ShaderMask` with a moving gradient). Motion is **disabled when
  `MediaQuery.of(context).disableAnimations` is true** — for accessibility and
  to keep widget tests free of pending timers.
- Declare `assets/images/` under `flutter:` assets in `pubspec.yaml`.

### Testing (TDD)

- `test/widget/menu_banner_test.dart`:
  - Menu renders the banner (`find.byType(MenuBanner)` / the asset `Image` is
    present).
  - With `disableAnimations = true`, no animation timers are pending (test
    settles cleanly).
- Native splash is configuration only — no automated test.

## File layout

```
tools/art/
  build_art.py            # renders scene(s) → assets/images/ (mirrors build_logo.py)
  splash_scene.blend      # source of truth for chosen splash art
  banner_scene.blend      # source of truth for chosen banner art
build/art/                # TEMP prototype renders (gitignored, Flatpak-writable)
assets/images/
  splash.png              # final, transparent
  menu_banner.png         # final, transparent
lib/ui/widgets/
  menu_banner.dart        # new animated banner widget
lib/ui/main_menu_screen.dart   # wire in banner
pubspec.yaml              # + flutter_native_splash dev_dep, config, assets/images/
test/widget/
  menu_banner_test.dart
.gitignore                # + build/art/
```

## Out of scope / YAGNI

- Pre-rendered Blender animation frames (GIF/sprite/video) — motion is done in
  Flutter over a static render.
- Baking the wordmark into the render — title stays Flutter text.
- Any change to `lib/core` or `lib/persistence`.
- Localization of the banner (art is text-free, so nothing to localize).

## Success criteria

- App shows a themed splash on launch (native, offline).
- Main menu shows the banner with a subtle, accessibility-respecting animation.
- Blender `.blend` sources + `build_art.py` committed as source of truth; final
  PNGs bundled; temp renders gitignored.
- `flutter analyze` + `flutter test` green; `dart format` clean; core/persistence
  Flutter-boundary check still passes.
