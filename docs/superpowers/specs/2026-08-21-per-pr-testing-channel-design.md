# Per-PR Testing Channel (F-Droid) — Design

**Date:** 2026-08-21
**Status:** Approved design, pre-implementation
**Scope:** CI/CD + Android build config only — no Dart/app code changes
**Builds on:** `2026-08-20-fdroid-self-hosted-repo-design.md` (the production
self-hosted F-Droid repo this extends)

## Purpose

Make it possible to test the changes in an open pull request on a real
device without a manual build + sideload, and without disturbing the
installed production app. Pushing to a PR branch should make that PR's build
appear in a dedicated **testing** F-Droid channel that is already added on
the phone.

The chosen model is a **single shared testing channel** (not one repo per
PR): one extra F-Droid repo, added to the client once, that holds a rolling
window of the **latest 3** PR builds of one side-by-side "testing" app. On
the device you keep a single testing app installed and switch between PR
builds via F-Droid's per-version list; each version is labelled and carries
a description of the PR's feature.

## Non-goals

- **Per-PR isolated repos.** One shared channel with a rolling window,
  not a repo per PR number.
- **Fork-PR support.** GitHub withholds Actions secrets from workflows
  triggered by forked PRs, so signing (hence publishing) is impossible for
  them. Only PRs from branches within this repo are supported. Fork PRs are
  detected and skipped with a clear log line.
- **Automatic downgrade handling.** Android forbids installing a lower
  `versionCode` over a higher one, so hopping from a newer PR build back to
  an older one requires F-Droid to uninstall + reinstall (the testing app's
  local data is lost). This is an Android limitation; it is documented, not
  worked around.
- **Tinted / badged testing icon (deferred).** v1 differentiates the
  testing app by *label* only ("Open Patience (Testing)"). A distinct icon
  is a fast-follow, and must go through the existing generated-icon pipeline
  (`flutter_launcher_icons` per-flavor config) — never a hand-edited PNG,
  per CLAUDE.md.
- **iOS / other platforms.** Android only.

## Related change already applied

The production `release.yml` publish step now sets `force_orphan: true`, so
`gh-pages` is flattened to a single orphan commit per release and old APK
blobs no longer accumulate in git history. This design must coexist with
that: see **Concurrency** below.

## Architecture & data flow

```
Pull request opened / synchronized / reopened  (base = main, head = same repo)
     │
     ▼
GitHub Actions: new workflow  .github/workflows/pr-channel.yml
     │  (skips immediately, with a log line, if head repo != base repo → fork)
     │
     ├─ flutter build apk --release --flavor testing \
     │      --build-number=$GITHUB_RUN_NUMBER \
     │      --build-name=pr<PR>-<slug>
     │   → applicationId io.github.d_rk.openpatience.debug   (side-by-side)
     │   → signed with the *testing app* keystore (CI secret)
     │
     ├─ checkout gh-pages  (contains production repo/ AND testing/)
     │
     ├─ prune testing/repo/*.apk to the newest 2 (new build makes 3);
     │   drop orphaned testing/.../changelogs/*.txt with no matching APK
     │
     ├─ copy new APK into testing/repo/
     ├─ write testing/metadata/<pkg.debug>/en-US/changelogs/<versionCode>.txt
     │      = PR title + first paragraph of PR body
     ├─ fdroid update  → regenerates testing/ index, signed with the
     │      *testing repo* keystore (CI secret)
     │
     └─ publish whole tree back to gh-pages (concurrency-serialized with release)
              │
              ▼
     GitHub Pages serves https://d-rk.github.io/open-patience/testing/repo
              │
              ▼
     F-Droid app on the phone (testing repo added once) shows the PR build;
     tap a version to install/switch.
```

## Component 1 — Android build config (`android/app/build.gradle.kts`)

Introduce a `channel` flavor dimension with two flavors:

- **`production`** — default `applicationId`
  (`io.github.d_rk.openpatience`), existing `release` signing config. This
  preserves today's production output exactly.
- **`testing`** — `applicationIdSuffix = ".debug"` (installs alongside
  production), a new `testing` signing config, and app label
  **"Open Patience (Testing)"**.

Details:

- **App label** comes from a flavor-specific `resValue`/manifest placeholder
  so `production` keeps the current label and `testing` overrides it. The
  current label wiring in `android/app/src/main/AndroidManifest.xml` is
  adjusted to read the placeholder/resource.
- **Testing signing config** loads from a separate `key.testing.properties`
  (same shape as the existing `key.properties`), guarded by a
  `hasTestingKeystore` file-exists check that mirrors the existing
  `hasReleaseKeystore` fallback — so local `flutter build --flavor testing`
  without the testing key still falls back to debug signing.
- Both flavors build in **release** mode. The production release build
  invocation in `release.yml` gains `--flavor production` (behaviourally a
  no-op — same applicationId, same signing, same artifact).

## Component 2 — `pr-channel.yml` workflow

Trigger: `pull_request` with `types: [opened, synchronize, reopened]` and
`branches: [main]`.

Steps:

1. **Fork guard.** If
   `github.event.pull_request.head.repo.full_name != github.repository`,
   log "skipping testing-channel publish for fork PR" and exit 0.
2. **Flutter setup + `pub get`** (matches existing workflows).
3. **Decode testing app keystore** from `TESTING_ANDROID_KEYSTORE_BASE64`;
   write `android/key.testing.properties` from the `TESTING_ANDROID_*`
   secrets.
4. **Compute version fields.**
   - `versionCode = $GITHUB_RUN_NUMBER` (unique, monotonic).
   - `slug` = PR title lowercased, non-alphanumerics → `-`, collapsed,
     truncated (~30 chars).
   - `versionName = pr<PR_NUMBER>-<slug>`.
5. **Build:** `flutter build apk --release --flavor testing
   --build-number=$versionCode --build-name=$versionName`.
6. **Install fdroidserver** (pip), matching `release.yml`.
7. **Checkout `gh-pages`** into a working dir (`fetch-depth: 1` is
   sufficient — the testing index is regenerated, and production history is
   now orphan-flattened anyway).
8. **Decode testing repo keystore** from `TESTING_FDROID_KEYSTORE_BASE64`;
   write `testing/config.yml` (its own `repo_url`
   `.../open-patience/testing/repo`, `repo_name`/`repo_description` marking
   it a testing channel, `keystore`, `keystorepass`).
9. **Prune:** keep the newest 2 existing `testing/repo/*.apk` by embedded
   versionCode (the new build becomes the 3rd); delete
   `testing/metadata/<pkg.debug>/en-US/changelogs/*.txt` whose versionCode
   has no surviving APK.
10. **Stage new APK** into `testing/repo/` as
    `open-patience-testing-<versionCode>.apk`.
11. **Write changelog** `testing/metadata/<pkg.debug>/en-US/changelogs/<versionCode>.txt`
    from PR title + first paragraph of the PR body.
12. **`fdroid update --create-metadata`** in `testing/` → regenerates the
    signed index over the ≤3 retained builds.
13. **Publish** to `gh-pages` with `peaceiris/actions-gh-pages@v4`,
    `exclude_assets` for the testing `keystore`/`config.yml`. See
    Concurrency for the required settings.

`<pkg.debug>` throughout = `io.github.d_rk.openpatience.debug`.

## Component 3 — Concurrency (shared `gh-pages` branch)

GitHub Pages serves only one branch, so the testing repo lives as a
subdirectory of `gh-pages` alongside the production `repo/`. Both
`release.yml` and `pr-channel.yml` therefore push to `gh-pages` and must not
race.

- Add the **same** concurrency group to **both** workflows:
  `concurrency: { group: gh-pages-publish, cancel-in-progress: false }` so
  runs queue instead of overwriting each other.
- Each job checks out the **whole** `gh-pages` tree and mutates only its own
  subtree (`repo/` + top-level `metadata/` for release; `testing/` for PR),
  then republishes the whole tree. Because each publish mirrors a tree that
  still contains the other channel's files, neither channel wipes the other.
- The production `force_orphan: true` flattens history but preserves the
  full working tree it publishes (including `testing/`), so it does not
  delete the testing channel.

## Secrets & one-time manual setup

Two new persistent keystores → new repo secrets (must never rotate once in
use, same discipline as the production keys):

- **Testing app signing:** `TESTING_ANDROID_KEYSTORE_BASE64`,
  `TESTING_ANDROID_KEY_ALIAS`, `TESTING_ANDROID_KEY_PASSWORD`,
  `TESTING_ANDROID_STORE_PASSWORD`.
- **Testing repo index signing:** `TESTING_FDROID_KEYSTORE_BASE64`,
  `TESTING_FDROID_KEYSTORE_PASSWORD`.

The implementation plan will include the exact `keytool` (generate) and
`base64` (encode-for-secret) commands. Creating the keystores, storing the
secrets, and adding the testing repo URL in the F-Droid client are manual
steps the maintainer performs once — CI cannot do them.

## Testing / verification

No Dart logic changes, so the unit/widget/integration suites are unaffected.
Verification is CI- and build-config-side:

- **Local (headless, by the implementer):**
  `flutter build apk --release --flavor testing` builds and yields an APK
  whose applicationId ends in `.debug` and whose label is
  "Open Patience (Testing)"; `flutter build apk --release --flavor
  production` is byte-for-byte equivalent in identity to today's output.
  `fdroid update` on a scratch `testing/` dir with 3 dummy APKs produces a
  valid signed index and honours the changelog files.
- **End-to-end (maintainer, acceptance):** open a test PR → the testing
  channel gains the build → add the channel in F-Droid on a device → the
  testing app installs side-by-side with production and shows the PR's
  version label + description. This step cannot be run headlessly and is the
  acceptance gate.

## Risks & caveats

- **Downgrade wipes testing data** (Android limitation) — documented above.
- **Fork PRs unsupported** — documented; acceptable for a solo project.
- **Concurrency is mandatory** — without the shared group, an overlapping
  release + PR publish can clobber one channel. The design makes both
  workflows share the group.
- **Rolling window is the only retention** — keeping the newest 3 self-bounds
  testing-channel growth, so no PR-close cleanup workflow is required.
