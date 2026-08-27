# tools/ — developer scripts

Build/authoring scripts that regenerate committed assets or drive F-Droid
release plumbing. None of them run in the app or in CI's test lane; they are
run by hand when their inputs change, and their **outputs are committed**.
Each script is the single source of truth for the files it emits — edit the
script (or its source scene/SVG), re-run, commit the regenerated output. Never
hand-edit a generated PNG.

## Layout

```
tools/
  art/     Blender-rendered splash + menu banner art
  logo/    app icon + launcher/web/F-Droid icons (pure-SVG → PNG)
  fdroid/  F-Droid release plumbing + store screenshots
```

## art/ — splash & menu banner

- `build_art.py` — loads the two editable Blender scenes and renders the
  transparent PNGs the app bundles.
- `splash_scene.blend`, `banner_scene.blend` — the editable source art (fanned
  hand of cards; fonts packed into the .blend, so no external font files).
  `*.blend1` are Blender's autosave backups.

Outputs: `assets/images/splash.png`, `assets/images/splash_android12.png`
(camera pulled back to clear the Android-12 circular safe zone),
`assets/images/menu_banner.png`.

Run (Blender is a Flatpak here):

```bash
flatpak run org.blender.Blender --background --python tools/art/build_art.py
# or, with a normal install:
blender --background --python tools/art/build_art.py
```

The .blend files are the source of truth — edit them in Blender, then re-run.

## logo/ — app icon & icon set

- `build_logo.py` — the single source of truth for the icon. Generates the logo
  as SVG (three overlapping cards in the Emerald Felt palette) purely in code,
  then rasterises it via **Inkscape** into every icon PNG the app needs.
- `logo.svg`, `logo_foreground.svg`, `logo_maskable.svg` — inspectable SVGs the
  script writes next to itself (opaque tile, adaptive foreground, maskable).

Outputs:
- `assets/icon/icon.png` (opaque full-bleed tile, 1024px) +
  `assets/icon/icon_foreground.png` (adaptive foreground, 1024px)
- `metadata/en-US/images/icon.png` (512px F-Droid listing icon)
- `web/icons/Icon-192.png`, `Icon-512.png`, `Icon-maskable-192.png`,
  `Icon-maskable-512.png` (PWA icons; maskable = cards scaled into the 80 %
  safe zone on felt)

Needs Inkscape on PATH, plus a serif font (Liberation Serif) and a suit-glyph
font (Noto Sans Symbols / Symbols 2) for the rank letters and pips.

```bash
python3 tools/logo/build_logo.py       # regenerate all icon PNGs + SVGs
dart run flutter_launcher_icons        # then rebuild platform launcher icons
```

Edit the palette or the `CARDS` layout in `build_logo.py` — never an icon PNG.

## fdroid/ — release plumbing & screenshots

- `capture_screenshots.py` — captures the F-Droid store screenshots from the
  Flutter **web** build. Pure stdlib (a tiny bundled WebSocket + Chrome
  DevTools Protocol client — like `build_logo.py` shelling out to Inkscape, it
  needs only the `google-chrome` binary). It serves `build/web`, drives headless
  Chrome at a realistic *logical* viewport and device pixel ratio (phone
  360×640 @3× → 1080×1920; tablet 960×600 @2× → 1920×1200), taps through the UI,
  and writes numbered PNGs.
  - Because Flutter renders to a single `<canvas>` there are no DOM handles;
    navigation is coordinate-based and tuned to the fixed viewport. Retune the
    `FORMATS` coords (in **logical** pixels) if the menus move.
  - Outputs three shots per form factor — main menu, a fresh Klondike deal, a
    fresh FreeCell deal — into
    `metadata/en-US/images/{phoneScreenshots,tenInchScreenshots}/`.

  ```bash
  flutter build web --release                          # prerequisite
  python3 tools/fdroid/capture_screenshots.py          # phone (portrait)
  python3 tools/fdroid/capture_screenshots.py --tablet # tablet (landscape)
  ```

  (The script builds `build/web` itself if it is missing.)

- `build_feature_graphic.py` — the single source of truth for the F-Droid
  listing **feature graphic** (`metadata/en-US/images/featureGraphic.png`,
  1024×500). Composes it as SVG — the Emerald Felt gradient, the shared
  `assets/images/menu_banner.png` art, and the `OPEN PATIENCE` wordmark + gold
  suit-pip rule (mirroring the main menu's lockup) — and rasterises via
  **Inkscape**, the same pattern as `build_logo.py`. Writes an inspectable
  `feature_graphic.svg` next to itself (banner referenced by relative path, so
  it stays small; the rasterised copy inlines the banner as base64 to be
  CWD-independent). Needs Inkscape + Noto Sans Symbols (suit glyphs); the
  bundled `assets/fonts/LilitaOne-Regular.ttf` is exposed to Inkscape via a
  throwaway fontconfig file, so no system font install is required.

  ```bash
  python3 tools/fdroid/build_feature_graphic.py
  ```

  Edit the palette / layout in the script — never the PNG.

- `release.sh` — cut a release interactively. Preflight (clean tree, on `main`,
  not behind `origin`) → pick the new versionName (defaults to a patch bump;
  the versionCode auto-increments) → require both `en-US` + `de-DE` changelogs
  for the new code (opens `$EDITOR` for any missing) → verify every generated
  asset is up to date (`--skip-verify` to bypass) → rewrite the single
  `pubspec.yaml` `version:` line → commit `chore(release): vX.Y.Z (code N)`,
  annotated-tag `vX.Y.Z`, and (on confirmation) `git push --follow-tags`.
  pubspec is the *only* committed version source (`android/local.properties` is
  gitignored and regenerated from it). The verify step runs all four generators
  (`build_art.py`, `build_logo.py`, `build_feature_graphic.py`,
  `capture_screenshots.py` ×2) and aborts if any tracked output changed — so it
  needs Blender, Inkscape, Chrome and Flutter present; `--skip-verify` is the
  escape hatch when the toolchain is absent or a render isn't byte-stable.

  ```bash
  tools/fdroid/release.sh                # full release, verifying assets
  tools/fdroid/release.sh --skip-verify  # skip asset regeneration/diff-check
  tools/fdroid/release.sh --verify-only  # ONLY audit assets; no bump/commit/tag
  ```

- `write-pr-changelog.sh` — writes an F-Droid per-version changelog
  (`<changelogs_dir>/<versionCode>.txt`) from a PR title + first body paragraph.
- `prune-testing-apks.sh` — keeps only the newest N testing APKs in a repo dir
  and drops orphaned changelogs. Both are wired into the CI/release workflow.
- `test/*.test.sh` — plain-bash tests for the shell scripts above (including
  `release.test.sh` for the pure version/changelog helpers, `release-flow.test.sh`
  for the end-to-end flow, and `release-verify.test.sh` for `--verify-only`, all
  in throwaway repos). Run them directly:
  `bash tools/fdroid/test/prune-testing-apks.test.sh`.
- `verify-reproducible-build.sh` — diagnostic tool: proves (or disproves)
  whether this app's release build is *path-reproducible*, without burning a
  full CI cycle finding out. A Dart AOT snapshot embeds the absolute
  filesystem path of the app source root it was compiled from — `--obfuscate`
  does **not** strip this — so two builds only produce an identical
  `libapp.so` if both build from the same absolute path. The script builds the
  given commit/ABI **twice**, in two independent, freshly provisioned Docker
  containers (root inside, so `/home/runner/work/...` can be created without
  needing host sudo — the path GitHub Actions' default checkout uses), and
  diffs the resulting `libapp.so` hash. Each container clones this repo from a
  read-only bind mount (no GitHub network dependency) and fetches Flutter
  fresh (so a stale/mutated SDK checkout can never quietly explain a false
  match).

  ```bash
  tools/fdroid/verify-reproducible-build.sh              # HEAD, arm64-v8a, flutter 3.38.5
  tools/fdroid/verify-reproducible-build.sh v1.0.4 x86_64
  ```

  Needs Docker and the host's Android SDK at `/opt/android/sdk` (bind-mounted
  read-only into each container — this only saves a slow multi-GB SDK
  download; it is not part of what's being tested).

  **Known limitation:** this only isolates *path*-based non-determinism. It
  does not control for Android SDK/build-tools/NDK version — when checked
  against the real GitHub Actions-built v1.0.4 APK, the container's libapp.so
  did NOT match, because the container reused the host's installed SDK rather
  than GitHub's runner SDK. That gap is why F-Droid's reproducible-build
  support was dropped for this app (see git history around v1.0.4) rather than
  chased further — F-Droid signs the app with its own key instead. Re-run
  this script for its original purpose only if reproducible builds are
  revisited, and pin a matching Android SDK/build-tools/NDK version in the
  container first.

## Notes

- **F-Droid store metadata lives at the repo root in `metadata/<locale>/`** —
  the standard fastlane-style layout scanned by the *main* F-Droid repo
  (`title.txt`, `short_description.txt`, `full_description.txt`,
  `images/icon.png`, `images/phoneScreenshots/`, `images/tenInchScreenshots/`).
  `build_logo.py` and `capture_screenshots.py` write the icon + screenshots
  there. The *self-hosted* repo's `.github/workflows/release.yml` maps the
  `metadata/<locale>/` dirs into the collection path
  `fdroid-repo/metadata/<packageId>/<locale>/` before running `fdroid update`,
  so both the main repo and your own repo consume the same source of truth.
  Alongside them sits `metadata/<packageId>.yml` — the app-info recipe
  (Categories, License, links), not store text/graphics; the workflow copies it
  to `fdroid-repo/metadata/<packageId>.yml`.
- Screenshot buckets must use F-Droid's recognized names: `phoneScreenshots`,
  `sevenInchScreenshots`, `tenInchScreenshots`, `tvScreenshots`,
  `wearScreenshots` (hence the landscape set is `tenInchScreenshots`, not
  `tabletScreenshots`).
- `tools/fdroid/__pycache__/` is Python bytecode cache — not source, keep it out
  of commits.
- Adding the web platform for screenshots created the committable `web/`
  scaffold; `capture_screenshots.py` depends on it.
