# Solitaire

A cross-platform solitaire game built in Flutter, with Klondike (draw-1,
draw-3) and FreeCell. Built as a vehicle for clean, testable architecture —
see `CLAUDE.md` and `docs/superpowers/specs/` for the design.

## Install

The Android build is self-published to a personal F-Droid repo — every push
to `main` builds a new signed release automatically.

1. In F-Droid: **Settings → Repositories → +** and add:
   ```
   https://d-rk.github.io/solitaire/repo
   ```
2. F-Droid will show a fingerprint to confirm before adding the repo. It
   should be:
   ```
   DE:B8:5A:53:E9:BA:3C:CA:E5:D6:02:45:D4:EA:D7:5B:5A:C9:69:2F:A7:E9:78:2B:4A:37:B0:21:CA:2E:C9:9B
   ```
3. Find "Solitaire" under the new repo and install it from there. Installing
   from F-Droid (rather than a sideloaded APK) is what lets future pushes
   show up as an in-app update.
4. From then on, a normal F-Droid sync (automatic or pull-to-refresh) picks
   up new releases as they're published.

See `docs/superpowers/specs/2026-08-20-fdroid-self-hosted-repo-design.md`
for how the publish pipeline works.

## Development

```bash
flutter pub get      # install dependencies
flutter analyze      # static analysis
flutter test         # unit + widget suite
flutter test integration_test   # golden-path suite (real device/emulator)
flutter run           # run the app locally
```

Full contributor guidance — architecture, TDD workflow, style — is in
`CLAUDE.md`.
