# Contributing to Open Patience

This is a guide for working on the code — not for installing the app as a
player. `CLAUDE.md` is the authority on architecture and TDD; this document
summarises the parts a new contributor needs on day one and links out for
detail.

## Getting started

```bash
flutter pub get      # install dependencies
flutter analyze      # static analysis
flutter test         # unit + widget suite
flutter test integration_test   # golden-path suite (real device/emulator)
flutter run --flavor production   # run the app locally
```

One-time setup, once per clone:

```bash
git config core.hooksPath .githooks   # rejects commits with an AI co-author trailer
```

That hook is a technical backstop for the "commit authorship stays human"
rule in `CLAUDE.md`: it rejects any commit message that credits an AI
agent/tool as (co-)author.

## Architecture

`core/` and `presentation/`+`ui/` are strictly layered, arrows pointing one
way: UI depends on the game engine, never the reverse. See `CLAUDE.md` for
the full breakdown (`GameState`, `GameRules`, `Move`, the Bloc seam, and so
on). The two rules a new contributor trips over first:

- **Game logic never imports Flutter.** Everything in `lib/core/` and
  `lib/persistence/` is pure Dart, with zero `package:flutter` imports —
  enforced by a CI grep check.
- **A new solitaire variant is one new file in `lib/core/games/`** behind
  the `GameRules` interface — never a change to a widget.

## Test-driven development

TDD is mandatory here: RED (write a failing `flutter_test` test) → GREEN
(minimum code to pass) → REFACTOR (clean up, tests still green). No
production code is written before a failing test that requires it.

Presentation tests are split into two tiers:

- **Widget tests** (`test/widget/`) — every happy-path interaction flow,
  run on every push.
- **`integration_test`** — a couple of golden-path flows on a real
  device/emulator, run less often (a separate CI lane or pre-release gate).

Before committing, run through the pre-commit checklist in `CLAUDE.md`
(test-first, `flutter analyze`/`flutter test` clean, `dart format`, no
Flutter imports leaking into `core`/`persistence`, etc.).

## Generated assets

Icons, splash/banner art and F-Droid store screenshots are produced by
scripts under `tools/` — each script is the single source of truth for the
files it emits (`art/`, `logo/`, `fdroid/`, `video/`). To change an output,
edit the script (or its source `.blend`/SVG) and re-run it; never hand-edit
a generated PNG. See `tools/CLAUDE.md` for what each script owns and how to
run it.

### App icon

The launcher icon is three overlapping playing cards — a Queen of clubs and
King of hearts fanned behind a hero Ace of spades — in the "Emerald Felt"
palette (cream cards, gold edges, dark-green felt). The single source of
truth is `tools/logo/build_logo.py`: it generates the logo as SVG and
rasterises it into the icon PNGs. Edit the palette or the `CARDS` layout in
that script (it also writes `tools/logo/logo.svg` +
`tools/logo/logo_foreground.svg`, which you can open in Inkscape to eyeball
the art).

To regenerate the icons:

```bash
# 1. Generate assets/icon/icon.png (opaque full-bleed felt tile),
#    assets/icon/icon_foreground.png (Android adaptive foreground) and the
#    512px F-Droid listing icon. Needs Inkscape plus a serif font
#    (Liberation Serif) and a suit-glyph font (Noto Sans Symbols).
python3 tools/logo/build_logo.py

# 2. Rebuild the platform launcher icons from those PNGs.
dart run flutter_launcher_icons
```

Icon settings (image paths, adaptive background colour) live under the
`flutter_launcher_icons:` key in `pubspec.yaml`.

## Developer install channels

These are routes for trying in-development builds, not how end users get
the app — see the README's Install section for that.

### Self-hosted F-Droid repo

Every push to `main` builds a new signed release and publishes it to a
personal F-Droid repo:

1. In F-Droid: **Settings → Repositories → +** and add:
   ```
   https://d-rk.github.io/open-patience/repo
   ```
2. F-Droid will show a fingerprint to confirm before adding the repo. It
   should be:
   ```
   DE:B8:5A:53:E9:BA:3C:CA:E5:D6:02:45:D4:EA:D7:5B:5A:C9:69:2F:A7:E9:78:2B:4A:37:B0:21:CA:2E:C9:9B
   ```
3. Find "Open Patience" under the new repo and install it from there.
   Installing from F-Droid (rather than a sideloaded APK) is what lets
   future pushes show up as an in-app update.
4. From then on, a normal F-Droid sync (automatic or pull-to-refresh) picks
   up new releases as they're published.

How the publish pipeline itself works is described in a maintainer-local
design note (kept outside the repo); the scripts and workflows under
`tools/fdroid/` and `.github/workflows/` are the authoritative version.

### Testing channel (per-PR builds)

Every pull request from a branch in this repo is built and published to a
separate **testing** F-Droid channel, so you can try a PR on a device
without touching the production app. The testing app installs side-by-side
(applicationId `io.github.d_rk.openpatience.debug`, labelled
"Open Patience (Testing)"), and the channel keeps the **latest 3** PR builds.

**One-time setup on your phone:** add this repo in the F-Droid client:

```
https://d-rk.github.io/open-patience/testing/repo
```

Each build shows up as a version labelled `pr<number>-<slug>`; tap a version
to install or switch to it. The per-version "What's New" holds the PR title
and summary.

**Caveats:**
- Switching to a *newer* build is a normal update. Switching *back* to an
  older build is an Android downgrade, so F-Droid must uninstall and
  reinstall — the testing app's saved game is lost (production is untouched).
- PRs from forks are not published (GitHub withholds the signing secrets
  from fork workflows).
- If several PRs push near-simultaneously, only the most recent queued
  testing-channel publish runs — older queued runs are superseded by the
  shared publish concurrency group — so a PR may need a fresh push to
  appear.

Setting up the keys and secrets behind this channel is a maintainer task —
see `RELEASING.md`.
