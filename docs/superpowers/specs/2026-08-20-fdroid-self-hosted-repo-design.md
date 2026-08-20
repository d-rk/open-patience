# Self-Hosted F-Droid Repo + Auto-Publish on Push — Design

**Date:** 2026-08-20
**Status:** Approved design, pre-implementation
**Scope:** CI/CD + Android build config only — no Dart/app code changes

## Purpose

Today, getting a build onto a phone means a manual `flutter build apk` +
sideload. The goal: pushing to `main` should produce a signed release build
that shows up as an available update in the F-Droid app already installed
on the phone, with no manual build/transfer step.

Android does not allow a fully silent install without root or F-Droid's
Privileged Extension (system-app only). This design targets the standard
F-Droid flow instead: push → CI builds, signs, and publishes → F-Droid
polls the repo in the background → an "update available" notification
appears → one tap installs it.

## Non-goals

- Publishing to the official F-Droid public repo (has a source-build,
  review, and inclusion process unsuited to a private personal project).
- A fully silent/unattended install (would require a rooted phone or
  Privileged Extension as a system app).
- Pruning/retention policy for old APKs in the repo — out of scope for v1,
  revisit if repo size becomes a problem.

## Architecture & data flow

```
git push (to main)
     │
     ▼
GitHub Actions: new "release" workflow (separate job from existing ci.yml)
     │
     ├─ flutter build apk --release --build-number=$GITHUB_RUN_NUMBER
     │  signed with a persistent *app signing* keystore (from a CI secret)
     │
     ├─ checkout the gh-pages branch into a working dir — this branch IS
     │  the F-Droid repo and retains every past APK, so existing installs
     │  can always verify the update chain
     │
     ├─ copy the new APK into repo/, run `fdroid update` (fdroidserver)
     │  → regenerates index-v1.json / index-v2.json, icons, changelog
     │  → signs the index with a persistent *repo signing* keystore
     │    (separate key from the app signing key; also a CI secret)
     │
     └─ commit + push the updated repo back to gh-pages
              │
              ▼
     GitHub Pages serves https://d-rk.github.io/solitaire/
              │
              ▼
     F-Droid app on the phone (repo added once, one-time setup) polls this
     URL periodically → shows "update available" → tap to install
```

Two independent, persistent signing keys are required and must never
rotate once created:

- **App signing key** — signs the APK. Android refuses to install an
  "update" whose signature doesn't match the currently installed app, so
  this key must stay constant for the life of the app.
- **Repo signing key** — signs the F-Droid repo index (`fdroidserver`'s
  own mechanism). F-Droid pins a repo by its signing fingerprint when
  first added; a changed key means the client rejects the repo as
  untrusted and it has to be re-added from scratch.

Both are generated once, base64-encoded, and stored only as GitHub Actions
secrets — never committed to the repo.

## Decisions from brainstorming

| Question | Decision |
|---|---|
| Update UX | Standard F-Droid flow (notification + tap), not silent install |
| Repo hosting | GitHub Pages, served from `gh-pages` branch |
| Repo visibility | Public, unlisted URL (source repo itself stays private) |
| Build trigger | Push to `main` only |
| Versioning | `versionCode` auto-set to `$GITHUB_RUN_NUMBER` on every build; `versionName` stays from `pubspec.yaml` |
| Application ID | `io.github.d_rk.solitaire` (F-Droid's own convention for repos without a custom domain; hyphen in the GitHub handle `d-rk` becomes `_` since Android package segments disallow hyphens) |

## Changes to this repo

1. **`android/app/build.gradle.kts`**
   - `applicationId` changes from the placeholder `com.example.solitaire`
     to `io.github.d_rk.solitaire`.
   - `namespace` updated to match.
   - Release `signingConfig` reads keystore path + passwords from a
     `key.properties` file (gitignored). CI writes this file from secrets
     before building. If the file is absent (local dev), release builds
     fall back to the debug signing config, exactly as today — so
     `flutter run --release` keeps working for local testing without a
     keystore on the developer's machine.

2. **New `.github/workflows/release.yml`**
   - Separate workflow from the existing `ci.yml` (which keeps doing
     analyze/test/format/integration on every push/PR, unchanged).
   - Trigger: `push` to `main`.
   - Steps: checkout → set up Flutter → decode app-signing keystore
     secret → `flutter build apk --release --build-number=$GITHUB_RUN_NUMBER`
     → set up Python + `pip install fdroidserver` → checkout `gh-pages`
     branch into a working directory → decode repo-signing keystore
     secret → write `fdroidserver` `config.yml` → copy new APK into
     `repo/` → `fdroid update` → commit + push the updated `gh-pages`
     branch (e.g. via `peaceiris/actions-gh-pages` with `keep_files:
     true` so history isn't wiped each run).

3. **No Dart/Flutter source changes.** This is Android/Gradle + CI/CD
   only, so the TDD workflow in `CLAUDE.md` doesn't apply to this work —
   there's no `core`/`persistence`/`presentation` code being added.
   Verification is operational (see below), not `flutter test`.

## One-time setup (outside CI, done once)

- Generate the two release keystores locally with `keytool`, base64
  encode them, register as GitHub Actions secrets (`gh secret set`):
  app signing (keystore + key alias + key password + store password) and
  repo signing (keystore + password).
- Enable GitHub Pages on the repo, serving from the `gh-pages` branch
  (Settings → Pages, or `gh api repos/d-rk/solitaire/pages`). This is the
  step that makes the `gh-pages` branch content publicly reachable —
  done with explicit confirmation at implementation time, since the
  source repo itself is private.
- On the phone: add the repo to F-Droid once, using the URL and the
  fingerprint reported by the first successful `fdroid update` run.
  After that, F-Droid's normal periodic repo check takes over.

## Verification approach

No app logic changes, so there's no new `flutter test` coverage to add.
Verification is end-to-end and operational:

1. Push a commit to `main`, confirm the `release` workflow goes green.
2. Confirm the `gh-pages` branch contains a valid `index-v1.json` and the
   new APK under `repo/`.
3. Confirm GitHub Pages serves that content at the public URL.
4. One real device check: add the repo in F-Droid on the phone, confirm
   the app installs from it, then push a second commit and confirm
   F-Droid surfaces it as an available update (not a "new app").

## Risks / things to watch

- `fdroidserver` pulls in Python + Android SDK build-tooling (`aapt`)
  dependencies in CI — adds a few minutes to the release workflow. Not a
  concern since it only runs on `main`, not every push.
- `gh-pages` branch grows by one APK per release indefinitely (no
  retention policy in v1). For a personal project with infrequent
  releases this is fine; revisit if it becomes unwieldy.
- If either signing key is ever lost, the recovery path is a hard reset:
  a new app signing key means every existing install must be manually
  uninstalled/reinstalled; a new repo signing key means the repo must be
  re-added on every device. Both keystores should be backed up somewhere
  outside of CI secrets (they're by definition not recoverable from the
  repo itself).
