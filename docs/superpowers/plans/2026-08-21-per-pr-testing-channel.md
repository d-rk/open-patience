# Per-PR Testing Channel (F-Droid) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish every same-repo pull request as a side-by-side "testing" APK into a shared F-Droid channel that keeps the latest 3 builds, so PRs can be tested on a device without disturbing the production app.

**Architecture:** A new Gradle `channel` product flavor (`production` / `testing`) builds a `.debug`-suffixed, differently-labelled, differently-signed release APK. A new `pr-channel.yml` GitHub Actions workflow builds that flavor on same-repo PRs, prunes the testing repo to the latest 3, writes a per-version changelog from the PR title/body, regenerates the F-Droid index, and publishes it to a `testing/` subdirectory of the existing `gh-pages` branch. Both publish workflows share a concurrency group so they never clobber the shared branch. The prune and changelog logic live in standalone, unit-tested shell scripts under `tools/fdroid/`.

**Tech Stack:** Flutter (stable channel), Gradle Kotlin DSL (AGP 8.11.1), `fdroidserver` (pip), GitHub Actions, `peaceiris/actions-gh-pages@v4`, GitHub Pages.

**Spec:** `docs/superpowers/specs/2026-08-21-per-pr-testing-channel-design.md`

## Global Constraints

- Production applicationId stays exactly `io.github.d_rk.openpatience`; testing applicationId is exactly `io.github.d_rk.openpatience.debug` (via `applicationIdSuffix = ".debug"`).
- Testing app label is exactly `Open Patience (Testing)`; production label stays exactly `Open Patience`.
- Testing F-Droid repo URL is exactly `https://d-rk.github.io/open-patience/testing/repo`.
- Testing APK filename pattern is exactly `open-patience-testing-<versionCode>.apk`.
- Retention: keep exactly the newest **3** testing APKs (by versionCode).
- `versionCode = $GITHUB_RUN_NUMBER`; `versionName = pr<PR_NUMBER>-<slug>` (slug: PR title, lowercased, non-alphanumerics → `-`, trimmed, ≤30 chars).
- Shared Actions concurrency group name is exactly `gh-pages-publish`, with `cancel-in-progress: false`, on BOTH `release.yml` and `pr-channel.yml`.
- Only same-repo PRs are published (fork PRs are skipped — they have no secrets).
- No Dart/app-logic changes: the `flutter test` suite and the `lib/core` no-Flutter-imports boundary are untouched by this plan.
- Never interpolate `${{ github.event.pull_request.* }}` directly into a `run:` shell body — pass via `env:` and reference as `"$VAR"` (shell-injection safety).

---

### Task 1: Android `testing` flavor — suffix, label, signing

**Files:**
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Produces: two build variants `productionRelease` and `testingRelease`. `flutter build apk --release --flavor production` → `build/app/outputs/flutter-apk/app-production-release.apk` (applicationId `io.github.d_rk.openpatience`). `flutter build apk --release --flavor testing` → `build/app/outputs/flutter-apk/app-testing-release.apk` (applicationId `io.github.d_rk.openpatience.debug`, label `Open Patience (Testing)`).
- Consumes: an optional `android/key.testing.properties` (same shape as the existing `android/key.properties`: `storePassword`, `keyPassword`, `keyAlias`, `storeFile`). Absent locally → testing flavor falls back to debug signing.

- [ ] **Step 1: Write the failing verification (build the testing flavor)**

There is no unit-test harness for Gradle config; the test is that the flavored build produces an APK with the right identity. Run:

```bash
flutter build apk --release --flavor testing
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL with a Gradle error like `Could not find product flavor 'testing'` (the flavor does not exist yet).

- [ ] **Step 3: Make the app label a manifest placeholder**

In `android/app/src/main/AndroidManifest.xml`, change the hardcoded label:

```xml
    <application
        android:label="${appLabel}"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
```

- [ ] **Step 4: Add the testing keystore loader**

In `android/app/build.gradle.kts`, directly below the existing `hasReleaseKeystore` block, add:

```kotlin
val testingKeystorePropertiesFile = rootProject.file("key.testing.properties")
val testingKeystoreProperties = Properties()
val hasTestingKeystore = testingKeystorePropertiesFile.exists()
if (hasTestingKeystore) {
    testingKeystoreProperties.load(FileInputStream(testingKeystorePropertiesFile))
}
```

- [ ] **Step 5: Add the testing signing config**

In `android/app/build.gradle.kts`, inside `signingConfigs { ... }`, after the existing `release` block:

```kotlin
        if (hasTestingKeystore) {
            create("testing") {
                keyAlias = testingKeystoreProperties["keyAlias"] as String
                keyPassword = testingKeystoreProperties["keyPassword"] as String
                storeFile = file(testingKeystoreProperties["storeFile"] as String)
                storePassword = testingKeystoreProperties["storePassword"] as String
            }
        }
```

- [ ] **Step 6: Move signing to the flavors and add the flavor dimension**

In `android/app/build.gradle.kts`, replace the existing `buildTypes { release { signingConfig = ... } }` block with a release block that assigns no signingConfig (so the per-flavor signingConfig applies — the build type would otherwise take precedence), and add a `productFlavors` block after it:

```kotlin
    buildTypes {
        release {
            // signingConfig is assigned per-flavor below, so production and
            // testing sign with different keys. (A signingConfig set here
            // would take precedence over the flavor's and defeat that.)
        }
    }

    flavorDimensions += "channel"

    productFlavors {
        create("production") {
            dimension = "channel"
            manifestPlaceholders["appLabel"] = "Open Patience"
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // No key.properties (local dev) — fall back to debug signing
                // so `flutter run --release` still works.
                signingConfigs.getByName("debug")
            }
        }
        create("testing") {
            dimension = "channel"
            applicationIdSuffix = ".debug"
            manifestPlaceholders["appLabel"] = "Open Patience (Testing)"
            signingConfig = if (hasTestingKeystore) {
                signingConfigs.getByName("testing")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
```

- [ ] **Step 7: Run the testing build to verify it passes and has the right identity**

```bash
flutter build apk --release --flavor testing
$ANDROID_HOME/build-tools/*/aapt dump badging \
  build/app/outputs/flutter-apk/app-testing-release.apk | grep -E "package|application-label:"
```

Expected: build PASSES; `package: name='io.github.d_rk.openpatience.debug'` and `application-label:'Open Patience (Testing)'`. (If `aapt` is not on PATH, `unzip -p .../app-testing-release.apk AndroidManifest.xml` and confirm the build succeeded — the label/appId are set by the config above.)

- [ ] **Step 8: Verify the production flavor is unchanged**

```bash
flutter build apk --release --flavor production
$ANDROID_HOME/build-tools/*/aapt dump badging \
  build/app/outputs/flutter-apk/app-production-release.apk | grep -E "package|application-label:"
```

Expected: `package: name='io.github.d_rk.openpatience'` and `application-label:'Open Patience'`.

- [ ] **Step 9: Commit**

```bash
git add android/app/build.gradle.kts android/app/src/main/AndroidManifest.xml
git commit -m "build(android): add testing product flavor (side-by-side .debug app)"
```

---

### Task 2: Point `release.yml` at the production flavor + add concurrency group

**Files:**
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: the `production` flavor and its APK output path from Task 1.
- Produces: an unchanged production artifact (`io.github.d_rk.openpatience`), now built via `--flavor production`, published under a shared concurrency group `gh-pages-publish`.

- [ ] **Step 1: Add the concurrency group at the top level**

In `.github/workflows/release.yml`, directly after the `on:` block and before `jobs:`, add:

```yaml
concurrency:
  group: gh-pages-publish
  cancel-in-progress: false
```

- [ ] **Step 2: Add `--flavor production` to the build step**

Change the "Build signed release APK" step's command:

```yaml
      - name: Build signed release APK
        run: flutter build apk --release --flavor production --build-number="$GITHUB_RUN_NUMBER"
```

- [ ] **Step 3: Fix the APK copy path for the flavored output**

In the "Replace the previous APK with the new one" step, the source path changes from `app-release.apk` to `app-production-release.apk`:

```yaml
      - name: Replace the previous APK with the new one
        run: |
          mkdir -p fdroid-repo/repo
          rm -f fdroid-repo/repo/*.apk
          cp build/app/outputs/flutter-apk/app-production-release.apk \
            "fdroid-repo/repo/open-patience-${GITHUB_RUN_NUMBER}.apk"
```

- [ ] **Step 4: Verify the workflow still parses**

```bash
python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('release.yml OK')"
```

Expected: `release.yml OK`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci(release): build production flavor; serialize gh-pages publish"
```

---

### Task 3: Prune helper script — keep newest N testing APKs

**Files:**
- Create: `tools/fdroid/prune-testing-apks.sh`
- Test: `tools/fdroid/test/prune-testing-apks.test.sh`

**Interfaces:**
- Produces: `tools/fdroid/prune-testing-apks.sh <repo_dir> <changelogs_dir> <keep_count>`. Keeps the newest `<keep_count>` files matching `open-patience-testing-<versionCode>.apk` in `<repo_dir>` (highest versionCode = newest), deletes the rest, and deletes any `<changelogs_dir>/<code>.txt` whose `<code>` no longer has a surviving APK. Idempotent; exits 0. Missing dirs are treated as empty (no error).

- [ ] **Step 1: Write the failing test**

Create `tools/fdroid/test/prune-testing-apks.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../prune-testing-apks.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
repo="$work/repo"
logs="$work/changelogs"
mkdir -p "$repo" "$logs"

# Five builds, versionCodes 10..14, each with a matching changelog.
for c in 10 11 12 13 14; do
  echo "apk" > "$repo/open-patience-testing-$c.apk"
  echo "notes $c" > "$logs/$c.txt"
done
# A stray non-testing file must never be touched.
echo "keep me" > "$repo/README.txt"

bash "$script" "$repo" "$logs" 3

survivors="$(cd "$repo" && ls open-patience-testing-*.apk | sort)"
expected=$'open-patience-testing-12.apk\nopen-patience-testing-13.apk\nopen-patience-testing-14.apk'
[ "$survivors" = "$expected" ] || { echo "FAIL apks: got [$survivors]"; exit 1; }

logs_left="$(cd "$logs" && ls *.txt | sort)"
expected_logs=$'12.txt\n13.txt\n14.txt'
[ "$logs_left" = "$expected_logs" ] || { echo "FAIL logs: got [$logs_left]"; exit 1; }

[ -f "$repo/README.txt" ] || { echo "FAIL: stray file deleted"; exit 1; }
echo "PASS"
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash tools/fdroid/test/prune-testing-apks.test.sh
```

Expected: FAIL — `prune-testing-apks.sh` does not exist (`No such file or directory`).

- [ ] **Step 3: Write the script**

Create `tools/fdroid/prune-testing-apks.sh`:

```bash
#!/usr/bin/env bash
# Keep only the newest <keep_count> testing APKs (by versionCode embedded in
# the filename open-patience-testing-<code>.apk) in <repo_dir>, and drop any
# changelog <code>.txt in <changelogs_dir> with no surviving APK.
set -euo pipefail

repo_dir="${1:?usage: prune-testing-apks.sh <repo_dir> <changelogs_dir> <keep_count>}"
changelogs_dir="${2:?missing <changelogs_dir>}"
keep_count="${3:?missing <keep_count>}"

[ -d "$repo_dir" ] || exit 0

# Collect versionCodes, newest (highest) first.
codes="$(
  find "$repo_dir" -maxdepth 1 -name 'open-patience-testing-*.apk' -printf '%f\n' 2>/dev/null \
    | sed -E 's/^open-patience-testing-([0-9]+)\.apk$/\1/' \
    | grep -E '^[0-9]+$' \
    | sort -rn
)"

kept=0
declare -A keep_code=()
while IFS= read -r code; do
  [ -n "$code" ] || continue
  if [ "$kept" -lt "$keep_count" ]; then
    keep_code["$code"]=1
    kept=$((kept + 1))
  else
    rm -f "$repo_dir/open-patience-testing-$code.apk"
  fi
done <<< "$codes"

# Prune orphaned changelogs.
if [ -d "$changelogs_dir" ]; then
  for f in "$changelogs_dir"/*.txt; do
    [ -e "$f" ] || continue
    code="$(basename "$f" .txt)"
    if [ -z "${keep_code[$code]:-}" ]; then
      rm -f "$f"
    fi
  done
fi
```

Then make it executable:

```bash
chmod +x tools/fdroid/prune-testing-apks.sh
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash tools/fdroid/test/prune-testing-apks.test.sh
```

Expected: `PASS`.

- [ ] **Step 5: Commit**

```bash
git add tools/fdroid/prune-testing-apks.sh tools/fdroid/test/prune-testing-apks.test.sh
git commit -m "tools(fdroid): prune script keeping newest N testing APKs"
```

---

### Task 4: Changelog helper script — per-version "What's New"

**Files:**
- Create: `tools/fdroid/write-pr-changelog.sh`
- Test: `tools/fdroid/test/write-pr-changelog.test.sh`

**Interfaces:**
- Produces: `tools/fdroid/write-pr-changelog.sh <changelogs_dir> <versionCode> <pr_title> <pr_body>`. Creates `<changelogs_dir>` if needed and writes `<changelogs_dir>/<versionCode>.txt` containing the PR title, then a blank line, then the first paragraph of the body (everything up to the first blank line). Empty/whitespace body → just the title (no trailing blank line). Exits 0.

- [ ] **Step 1: Write the failing test**

Create `tools/fdroid/test/write-pr-changelog.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../write-pr-changelog.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
logs="$work/changelogs"

# With a multi-paragraph body: title + blank + first paragraph only.
bash "$script" "$logs" 42 "Fix edge swipe" $'First para line one.\nline two.\n\nSecond para ignored.'
got="$(cat "$logs/42.txt")"
expected=$'Fix edge swipe\n\nFirst para line one.\nline two.'
[ "$got" = "$expected" ] || { echo "FAIL body: got [$got]"; exit 1; }

# With an empty body: title only, no trailing blank line.
bash "$script" "$logs" 43 "Title only" ""
got2="$(cat "$logs/43.txt")"
[ "$got2" = "Title only" ] || { echo "FAIL empty: got [$got2]"; exit 1; }
echo "PASS"
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash tools/fdroid/test/write-pr-changelog.test.sh
```

Expected: FAIL — `write-pr-changelog.sh` does not exist.

- [ ] **Step 3: Write the script**

Create `tools/fdroid/write-pr-changelog.sh`:

```bash
#!/usr/bin/env bash
# Write an F-Droid per-version changelog: PR title, then (if present) a blank
# line and the first paragraph of the PR body.
set -euo pipefail

changelogs_dir="${1:?usage: write-pr-changelog.sh <changelogs_dir> <versionCode> <pr_title> <pr_body>}"
version_code="${2:?missing <versionCode>}"
pr_title="${3:?missing <pr_title>}"
pr_body="${4-}"

mkdir -p "$changelogs_dir"
out="$changelogs_dir/$version_code.txt"

# First paragraph = everything before the first blank line, with trailing
# whitespace/newlines stripped.
first_para="$(printf '%s\n' "$pr_body" | awk 'BEGIN{RS="\n\n"} {print; exit}' | sed -e 's/[[:space:]]*$//')"

if [ -n "$first_para" ]; then
  printf '%s\n\n%s\n' "$pr_title" "$first_para" > "$out"
else
  printf '%s\n' "$pr_title" > "$out"
fi
```

Then:

```bash
chmod +x tools/fdroid/write-pr-changelog.sh
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash tools/fdroid/test/write-pr-changelog.test.sh
```

Expected: `PASS`. (Note: `$(...)` strips the file's single trailing newline, so the `[ "$got" = "$expected" ]` comparisons match the content exactly.)

- [ ] **Step 5: Commit**

```bash
git add tools/fdroid/write-pr-changelog.sh tools/fdroid/test/write-pr-changelog.test.sh
git commit -m "tools(fdroid): PR changelog writer for testing channel"
```

---

### Task 5: `pr-channel.yml` workflow

**Files:**
- Create: `.github/workflows/pr-channel.yml`

**Interfaces:**
- Consumes: the `testing` flavor (Task 1), `tools/fdroid/prune-testing-apks.sh` (Task 3), `tools/fdroid/write-pr-changelog.sh` (Task 4), and the six new secrets (Task 6). Shares the `gh-pages-publish` concurrency group with `release.yml` (Task 2).
- Produces: a published testing F-Droid repo at `gh-pages:/testing/repo` holding ≤3 APKs of `io.github.d_rk.openpatience.debug`.

- [ ] **Step 1: Create the workflow file**

Create `.github/workflows/pr-channel.yml`:

```yaml
name: PR testing channel

on:
  pull_request:
    types: [opened, synchronize, reopened]
    branches: [main]

concurrency:
  group: gh-pages-publish
  cancel-in-progress: false

jobs:
  publish-testing-build:
    name: Build and publish PR APK to the testing F-Droid channel
    runs-on: ubuntu-latest
    # Fork PRs get no secrets, so signing/publishing is impossible. Skip them.
    if: github.event.pull_request.head.repo.full_name == github.repository
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Install dependencies
        run: flutter pub get

      - name: Decode testing app signing keystore
        env:
          TESTING_ANDROID_KEYSTORE_BASE64: ${{ secrets.TESTING_ANDROID_KEYSTORE_BASE64 }}
        run: |
          echo "$TESTING_ANDROID_KEYSTORE_BASE64" | base64 -d > android/app/app-testing.keystore

      - name: Write key.testing.properties
        env:
          TESTING_ANDROID_KEY_ALIAS: ${{ secrets.TESTING_ANDROID_KEY_ALIAS }}
          TESTING_ANDROID_KEY_PASSWORD: ${{ secrets.TESTING_ANDROID_KEY_PASSWORD }}
          TESTING_ANDROID_STORE_PASSWORD: ${{ secrets.TESTING_ANDROID_STORE_PASSWORD }}
        run: |
          cat > android/key.testing.properties <<EOF
          storePassword=${TESTING_ANDROID_STORE_PASSWORD}
          keyPassword=${TESTING_ANDROID_KEY_PASSWORD}
          keyAlias=${TESTING_ANDROID_KEY_ALIAS}
          storeFile=app-testing.keystore
          EOF

      - name: Compute version name (pr<number>-<slug>)
        id: ver
        env:
          PR_TITLE: ${{ github.event.pull_request.title }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
        run: |
          slug="$(printf '%s' "$PR_TITLE" \
            | tr '[:upper:]' '[:lower:]' \
            | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
            | cut -c1-30 \
            | sed -E 's/-+$//')"
          echo "version_name=pr${PR_NUMBER}-${slug}" >> "$GITHUB_OUTPUT"

      - name: Build signed testing APK
        run: |
          flutter build apk --release --flavor testing \
            --build-number="$GITHUB_RUN_NUMBER" \
            --build-name="${{ steps.ver.outputs.version_name }}"

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install fdroidserver
        run: pip install fdroidserver

      - name: Check out gh-pages into the repo working directory
        uses: actions/checkout@v4
        with:
          ref: gh-pages
          path: gh-pages
          fetch-depth: 1

      - name: Decode testing repo signing keystore
        env:
          TESTING_FDROID_KEYSTORE_BASE64: ${{ secrets.TESTING_FDROID_KEYSTORE_BASE64 }}
        run: |
          mkdir -p gh-pages/testing
          echo "$TESTING_FDROID_KEYSTORE_BASE64" | base64 -d > gh-pages/testing/keystore.p12

      - name: Write testing fdroidserver config.yml
        working-directory: gh-pages/testing
        env:
          TESTING_FDROID_KEYSTORE_PASSWORD: ${{ secrets.TESTING_FDROID_KEYSTORE_PASSWORD }}
        run: |
          cat > config.yml <<EOF
          repo_url: "https://d-rk.github.io/open-patience/testing/repo"
          repo_name: "d-rk's Open Patience TESTING repo"
          repo_description: "Per-PR testing builds of Open Patience. Not for daily use; keeps the latest 3 PR builds."
          repo_keyalias: "repokey"
          keystore: "keystore.p12"
          keystorepass: "${TESTING_FDROID_KEYSTORE_PASSWORD}"
          keypass: "${TESTING_FDROID_KEYSTORE_PASSWORD}"
          EOF
          chmod 600 config.yml keystore.p12

      - name: Stage new APK and changelog
        env:
          PR_TITLE: ${{ github.event.pull_request.title }}
          PR_BODY: ${{ github.event.pull_request.body }}
        run: |
          pkg="io.github.d_rk.openpatience.debug"
          repo_dir="gh-pages/testing/repo"
          logs_dir="gh-pages/testing/metadata/$pkg/en-US/changelogs"
          mkdir -p "$repo_dir" "$logs_dir"
          cp build/app/outputs/flutter-apk/app-testing-release.apk \
            "$repo_dir/open-patience-testing-${GITHUB_RUN_NUMBER}.apk"
          bash tools/fdroid/write-pr-changelog.sh \
            "$logs_dir" "$GITHUB_RUN_NUMBER" "$PR_TITLE" "$PR_BODY"
          bash tools/fdroid/prune-testing-apks.sh "$repo_dir" "$logs_dir" 3

      - name: Regenerate the testing F-Droid repo index
        working-directory: gh-pages/testing
        run: fdroid update --create-metadata

      - name: Publish updated repo to gh-pages
        uses: peaceiris/actions-gh-pages@v4
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: gh-pages
          publish_branch: gh-pages
          # force_orphan mirrors the production release workflow: gh-pages is
          # rewritten as a single orphan commit, so old testing APK blobs do
          # not accumulate in history. publish_dir is the full gh-pages tree we
          # checked out and mutated, so the production repo/ is preserved.
          force_orphan: true
          exclude_assets: 'testing/keystore.p12,testing/config.yml'
```

- [ ] **Step 2: Verify the workflow parses**

```bash
python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/pr-channel.yml')); print('pr-channel.yml OK')"
```

Expected: `pr-channel.yml OK`.

- [ ] **Step 3: Verify no unsafe direct interpolation of PR text into shell**

```bash
grep -nE '\$\{\{ *github\.event\.pull_request\.(title|body)' .github/workflows/pr-channel.yml
```

Expected: matches appear ONLY inside `env:` blocks (right-hand side of `PR_TITLE:` / `PR_BODY:` / `PR_NUMBER:`), never inside a `run:` command line. Confirm by eye.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/pr-channel.yml
git commit -m "ci: publish PR builds to a testing F-Droid channel"
```

---

### Task 6: Documentation — testing channel + one-time key/secret setup

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: everything above. Documents the manual, one-time maintainer steps CI cannot perform (generate keystores, store secrets, add the repo in F-Droid) and the known caveats.

- [ ] **Step 1: Find where the production F-Droid repo is documented**

```bash
grep -n -i "f-droid\|fdroid\|gh-pages" README.md
```

Note the heading of the existing F-Droid section so the new subsection sits directly after it.

- [ ] **Step 2: Add a "Testing channel (per-PR builds)" subsection**

Insert immediately after the existing F-Droid section in `README.md`:

````markdown
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
````

- [ ] **Step 3: Verify the docs render / links are intact**

```bash
grep -n "testing/repo\|TESTING_ANDROID_KEYSTORE_BASE64\|Open Patience (Testing)" README.md
```

Expected: the new subsection's repo URL, first secret name, and label all appear.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document the per-PR testing F-Droid channel and its setup"
```

---

## Acceptance (maintainer, not headless)

After the tasks land and the six secrets are set:

1. Open a PR from a branch in this repo. Confirm the `PR testing channel`
   workflow runs (not skipped) and goes green.
2. On a device with the testing repo added, confirm a version labelled
   `pr<number>-<slug>` appears with the PR summary as its "What's New", and
   installs side-by-side with the production app.
3. Push a second commit to the PR; confirm a new version appears and the
   channel still lists at most 3 builds.
4. Merge or push a few more PR builds; confirm `gh-pages` history stays flat
   (one orphan commit) and the production channel is unaffected.
```
