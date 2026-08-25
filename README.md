# Open Patience

Open Patience is a free, open-source solitaire game built in Flutter — no
ads, no tracking. It ships Klondike (draw-1, draw-3) and FreeCell, and is
built as a vehicle for clean, testable architecture — see `CLAUDE.md` and
`docs/superpowers/specs/` for the design.

*Solitär — kostenlos, quelloffen, werbefrei.*

## Install

The Android build is self-published to a personal F-Droid repo — every push
to `main` builds a new signed release automatically.

1. In F-Droid: **Settings → Repositories → +** and add:
   ```
   https://d-rk.github.io/open-patience/repo
   ```
2. F-Droid will show a fingerprint to confirm before adding the repo. It
   should be:
   ```
   DE:B8:5A:53:E9:BA:3C:CA:E5:D6:02:45:D4:EA:D7:5B:5A:C9:69:2F:A7:E9:78:2B:4A:37:B0:21:CA:2E:C9:9B
   ```
3. Find "Open Patience" under the new repo and install it from there. Installing
   from F-Droid (rather than a sideloaded APK) is what lets future pushes
   show up as an in-app update.
4. From then on, a normal F-Droid sync (automatic or pull-to-refresh) picks
   up new releases as they're published.

See `docs/superpowers/specs/2026-08-20-fdroid-self-hosted-repo-design.md`
for how the publish pipeline works.

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

#### Maintainer: one-time key and secret setup

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

## Development

```bash
flutter pub get      # install dependencies
flutter analyze      # static analysis
flutter test         # unit + widget suite
flutter test integration_test   # golden-path suite (real device/emulator)
flutter run --flavor production   # run the app locally
```

Full contributor guidance — architecture, TDD workflow, style — is in
`CLAUDE.md`.

One-time setup, once per clone:

```bash
git config core.hooksPath .githooks   # rejects commits with an AI co-author trailer
```

## App icon

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

## License

Open Patience is free software licensed under the **GNU Affero General
Public License v3.0** (AGPL-3.0-only) — see [`LICENSE`](LICENSE). You are
free to use, study, share and modify it; if you run a modified version as a
network service, the AGPL requires you to offer that version's source to its
users.
