# Releasing Open Patience

Maintainer-only guide to cutting a release and to the one-time secrets setup
behind the per-PR testing channel. Contributors don't need this file — see
`CONTRIBUTING.md` instead.

## Cutting a release

Cutting a release is scripted — run it from a clean `main`:

```bash
tools/fdroid/release.sh
```

It walks you through it: pick the new version name (the versionCode
auto-increments), write the `en-US` + `de-DE` "What's New" changelogs for the
release, and — after verifying every generated asset is still reproducible
from its source script — it bumps `pubspec.yaml`, commits, tags `vX.Y.Z`, and
(on confirmation) pushes. Pushing `main` is what triggers the self-hosted
F-Droid publish; the tag is what a future official-F-Droid inclusion tracks.

```bash
tools/fdroid/release.sh --skip-verify  # skip the asset regeneration/diff-check
tools/fdroid/release.sh --verify-only  # just audit the generated assets, nothing else
```

## What `--verify-only` covers

`--verify-only` re-runs four generators and fails if any committed output is
stale relative to its source: `tools/logo/build_logo.py` (app icon),
`tools/fdroid/build_feature_graphic.py` (F-Droid feature graphic),
`tools/art/build_art.py` (Blender splash/banner art), and
`tools/fdroid/capture_screenshots.py` (run twice — phone and `--tablet` — for
the store screenshots).

`tools/video/` is excluded from this check. The gameplay video/GIF are
generated locally and hosted on YouTube, not committed — `media/` is
gitignored except the committed poster-frame thumbnail
(`media/gameplay_thumbnail.png`). The video is the one generated asset that
is not byte-reproducible (frame timing varies run to run), so it was never
part of `--verify-only` to begin with; see `tools/CLAUDE.md`'s `video/`
section for the recording workflow.

**The screenshot half of `--verify-only` cannot currently pass, on
unmodified code, for two independent reasons:**

- `lib/ui/game_options_screen.dart:47,55` calls `randomSeed()` for every new
  deal, so store screenshots 2 and 3 (a "fresh Klondike deal" and a "fresh
  FreeCell deal") show a different randomly dealt board on every run. They
  are not reproducible by construction.
- `BOOT_SETTLE = 6.0` in `tools/fdroid/capture_screenshots.py` is
  intermittently too short: a capture sometimes fires before Flutter's first
  paint and writes a blank white PNG. Two consecutive capture runs on base
  code have been observed to produce three differing PNGs, with the blank
  one landing on a different shot each time.

Because the final diff check in `verify_generated_assets()`
(`tools/fdroid/release.sh`) calls `die` on any diff, both
`release.sh --verify-only` and a full `release.sh` run without
`--skip-verify` currently fail on the screenshot step. Until this is fixed,
`--skip-verify` is the practical path for cutting a release. This is a
pre-existing issue, not something this document proposes to fix.

## Maintainer: testing-channel keys and secrets

The testing channel needs two persistent keystores, separate from the
production ones. Generate them once and never rotate them:

```bash
# 1. Testing APP signing key (signs the .debug app).
keytool -genkeypair -v -keystore app-testing.keystore \
  -alias testingkey -keyalg RSA -keysize 2048 -validity 10000

# 2. Testing REPO signing key (signs the F-Droid index).
keytool -genkeypair -v -keystore testing-keystore.p12 \
  -storetype PKCS12 -alias repokey -keyalg RSA -keysize 2048 -validity 10000

# Base64-encode each for storage as a GitHub Actions secret:
base64 -w0 app-testing.keystore   # → TESTING_ANDROID_KEYSTORE_BASE64
base64 -w0 testing-keystore.p12   # → TESTING_FDROID_KEYSTORE_BASE64
```

Store these repository secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `TESTING_ANDROID_KEYSTORE_BASE64` | base64 of `app-testing.keystore` |
| `TESTING_ANDROID_KEY_ALIAS` | the app key alias (e.g. `testingkey`) |
| `TESTING_ANDROID_KEY_PASSWORD` | the app key password |
| `TESTING_ANDROID_STORE_PASSWORD` | the app keystore password |
| `TESTING_FDROID_KEYSTORE_BASE64` | base64 of `testing-keystore.p12` |
| `TESTING_FDROID_KEYSTORE_PASSWORD` | the repo keystore password |

The testing repo key uses alias `repokey` and one password for both store and
key, matching `pr-channel.yml`'s `config.yml`.
