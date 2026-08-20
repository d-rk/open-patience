# Self-Hosted F-Droid Repo + Auto-Publish on Push Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pushing to `main` builds a signed release APK, publishes it to a
self-hosted F-Droid repo on GitHub Pages, and the app already installed via
F-Droid on the phone picks it up as an "update available" notification.

**Architecture:** A new `.github/workflows/release.yml` (separate from the
existing `ci.yml`) builds and signs a release APK on every push to `main`,
runs `fdroidserver`'s `fdroid update` against a working copy of the
`gh-pages` branch to regenerate the F-Droid repo index, and pushes the
result back to `gh-pages`, which GitHub Pages serves publicly. Two
persistent signing keys (app signing, repo signing) are generated once,
stored only as GitHub Actions secrets, and never committed.

**Tech Stack:** Flutter/Gradle (Android build), GitHub Actions, Python
`fdroidserver`, `keytool`, `gh` CLI.

**Spec:** `docs/superpowers/specs/2026-08-20-fdroid-self-hosted-repo-design.md`

## Global Constraints

- Application ID: `io.github.d_rk.solitaire` (was placeholder `com.example.solitaire`).
- Repo hosting: GitHub Pages served from the `gh-pages` branch, public, unlisted URL.
- Build trigger: push to `main` only — not every branch, not PRs.
- Versioning: `versionCode` = `$GITHUB_RUN_NUMBER` on every release build; `versionName` stays as declared in `pubspec.yaml`.
- No Dart/Flutter source changes and no new `flutter test` coverage — this is CI/Android-config infra only, so the TDD workflow in `CLAUDE.md` does not apply; verification is operational (build succeeds, workflow run is green, repo index is valid, phone shows the update).
- Both signing keys (app signing, repo signing) must never rotate once created — back them up outside of GitHub secrets (they are not recoverable from the repo).

---

### Task 1: Ignore signing artifacts

**Files:**
- Modify: `.gitignore`

**Interfaces:**
- Produces: `.gitignore` entries that keep `key.properties` and any local keystore files from ever being committed. Later tasks (2, 3) write files matching these patterns into the working tree.

- [ ] **Step 1: Add ignore patterns**

Append to `.gitignore`:

```gitignore

# Release signing (never commit — see docs/superpowers/specs/2026-08-20-fdroid-self-hosted-repo-design.md)
android/key.properties
*.keystore
*.jks
*.p12
```

- [ ] **Step 2: Verify a matching file is actually ignored**

```bash
touch android/key.properties
git status --porcelain android/key.properties
```

Expected: no output (empty) — confirms git is ignoring it.

```bash
rm android/key.properties
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "Ignore release signing artifacts"
```

---

### Task 2: Change the Android application ID and wire up release signing

**Files:**
- Modify: `android/app/build.gradle.kts`

**Interfaces:**
- Consumes: `android/key.properties` (produced by Task 4's CI step, and by a developer manually for local release builds) with keys `storePassword`, `keyPassword`, `keyAlias`, `storeFile`. When this file is absent, falls back to the existing debug `signingConfig` — so local `flutter run --release` keeps working unchanged for anyone without a keystore.
- Produces: `applicationId = "io.github.d_rk.solitaire"` — every later task (3, 4, 7) that references the app's identity uses this exact value. `namespace` is left as `com.example.solitaire` deliberately (it only affects the internal `R`/`BuildConfig` package, not the app's public identity or how Android resolves the manifest's `.MainActivity`, so there's no need to move/rename the Kotlin source under `android/app/src/main/kotlin/`).

- [ ] **Step 1: Edit `android/app/build.gradle.kts`**

Change the `applicationId` line inside `defaultConfig`:

```kotlin
    defaultConfig {
        applicationId = "io.github.d_rk.solitaire"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
```

Add a keystore-properties loader above the `android {` block, and a real
release `signingConfig` with a debug fallback, replacing the whole file's
top and `signingConfigs`/`buildTypes` sections:

```kotlin
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.solitaire"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "io.github.d_rk.solitaire"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // No key.properties present (e.g. local dev machine) — fall
                // back to debug signing so `flutter run --release` still works.
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
```

- [ ] **Step 2: Verify it still builds without a keystore present (debug fallback path)**

```bash
flutter build apk --debug
```

Expected: `BUILD SUCCESSFUL`, produces `build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 3: Verify the new application ID took effect**

```bash
/opt/android/sdk/build-tools/36.1.0/aapt dump badging \
  build/app/outputs/flutter-apk/app-debug.apk | grep "package: name="
```

Expected: `package: name='io.github.d_rk.solitaire' ...`

- [ ] **Step 4: Commit**

```bash
git add android/app/build.gradle.kts
git commit -m "Set application ID to io.github.d_rk.solitaire and wire up release signing"
```

---

### Task 3: Generate the app signing keystore and register it as CI secrets

This is a one-time local operation, not a code change — no files in the
repo are touched. Passwords are generated randomly and never typed by a
human, to avoid them ending up in shell history as literals.

**Interfaces:**
- Produces: four GitHub Actions repository secrets consumed by Task 5's
  workflow: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`,
  `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`.

- [ ] **Step 1: Create a persistent, non-repo location for the keystore**

```bash
mkdir -p ~/.secrets/solitaire-fdroid
cd ~/.secrets/solitaire-fdroid
```

- [ ] **Step 2: Generate a random store password and key password**

```bash
export ANDROID_STORE_PASSWORD=$(openssl rand -base64 24)
export ANDROID_KEY_PASSWORD=$(openssl rand -base64 24)
export ANDROID_KEY_ALIAS=upload
```

- [ ] **Step 3: Generate the keystore**

```bash
keytool -genkeypair -v \
  -keystore app-release.keystore \
  -alias "$ANDROID_KEY_ALIAS" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$ANDROID_STORE_PASSWORD" -keypass "$ANDROID_KEY_PASSWORD" \
  -dname "CN=d-rk, OU=Solitaire, O=d-rk, L=, ST=, C=DE"
```

Expected: `[Storing app-release.keystore]`, file exists in the current directory.

- [ ] **Step 4: Register the four secrets on the GitHub repo**

```bash
gh secret set ANDROID_STORE_PASSWORD --repo d-rk/solitaire --body "$ANDROID_STORE_PASSWORD"
gh secret set ANDROID_KEY_PASSWORD --repo d-rk/solitaire --body "$ANDROID_KEY_PASSWORD"
gh secret set ANDROID_KEY_ALIAS --repo d-rk/solitaire --body "$ANDROID_KEY_ALIAS"
base64 -w0 app-release.keystore | gh secret set ANDROID_KEYSTORE_BASE64 --repo d-rk/solitaire
```

- [ ] **Step 5: Verify the secrets exist**

```bash
gh secret list --repo d-rk/solitaire
```

Expected: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`,
`ANDROID_STORE_PASSWORD` all listed.

- [ ] **Step 6: Back up the keystore file itself**

`~/.secrets/solitaire-fdroid/app-release.keystore` is the only copy outside
of the (write-only, unreadable-back) GitHub secret. Copy it to at least one
other durable location (password manager attachment, encrypted backup) — if
it's lost, every future release will be unable to update existing installs
of the app (per the spec's Risks section).

No git commit for this task — nothing in the repo changed.

---

### Task 4: Generate the F-Droid repo signing keystore and register it as CI secrets

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: two GitHub Actions repository secrets consumed by Task 5's
  workflow: `FDROID_KEYSTORE_BASE64`, `FDROID_KEYSTORE_PASSWORD`. Also
  produces the repo key alias value `repokey`, which Task 5's `config.yml`
  hardcodes as `repo_keyalias`.

- [ ] **Step 1: Set up a Python virtualenv and install fdroidserver**

```bash
cd ~/.secrets/solitaire-fdroid
python3 -m venv fdroid-venv
source fdroid-venv/bin/activate
pip install fdroidserver
```

If this fails to install on the local machine's Python version (fdroidserver's
native dependencies can lag behind the newest CPython release), pin an
older interpreter instead, e.g. via `pyenv install 3.11 && pyenv local 3.11`
before recreating the venv — do not skip ahead without a working
`fdroidserver`, since Step 3 needs it to generate a keystore in the exact
format the real `fdroid update` run in CI will expect.

- [ ] **Step 2: Scaffold a throwaway repo directory**

```bash
mkdir -p ~/.secrets/solitaire-fdroid/repo-bootstrap/repo
cd ~/.secrets/solitaire-fdroid/repo-bootstrap
export FDROID_KEYSTORE_PASSWORD=$(openssl rand -base64 24)
```

- [ ] **Step 3: Generate the repo signing keystore using fdroidserver's own tooling**

```bash
cat > config.yml <<EOF
repo_url: "https://d-rk.github.io/solitaire/repo"
repo_name: "d-rk's Solitaire repo"
repo_description: "Self-hosted F-Droid repo for the Solitaire app, published automatically from GitHub Actions."
repo_keyalias: "repokey"
keystore: "keystore.p12"
keystorepass: "$FDROID_KEYSTORE_PASSWORD"
keypass: "$FDROID_KEYSTORE_PASSWORD"
keydname: "CN=d-rk, OU=Solitaire repo, O=d-rk, C=DE"
EOF
fdroid update --create-metadata
```

Expected: a `keystore.p12` file is created in `repo-bootstrap/`, and
`repo/index-v1.json` / `repo/index-v2.json` are generated (the `repo/`
directory is empty of APKs at this point, so the index will just be empty
— that's fine, this run's only purpose is to produce a valid keystore in
fdroidserver's expected format).

- [ ] **Step 4: Register the two secrets on the GitHub repo**

```bash
base64 -w0 keystore.p12 | gh secret set FDROID_KEYSTORE_BASE64 --repo d-rk/solitaire
gh secret set FDROID_KEYSTORE_PASSWORD --repo d-rk/solitaire --body "$FDROID_KEYSTORE_PASSWORD"
```

- [ ] **Step 5: Verify the secrets exist**

```bash
gh secret list --repo d-rk/solitaire
```

Expected: `FDROID_KEYSTORE_BASE64` and `FDROID_KEYSTORE_PASSWORD` now also
listed, alongside the four from Task 3.

- [ ] **Step 6: Back up the keystore file**

Same reasoning as Task 3, Step 6 — `keystore.p12` is unrecoverable if lost;
copy it to durable storage outside of `~/.secrets/`.

No git commit for this task — nothing in the repo changed.

---

### Task 5: Add the release workflow

**Files:**
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: the six secrets produced by Tasks 3 and 4
  (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`,
  `ANDROID_STORE_PASSWORD`, `FDROID_KEYSTORE_BASE64`,
  `FDROID_KEYSTORE_PASSWORD`); the `android/key.properties` contract from
  Task 2 (`storePassword`, `keyPassword`, `keyAlias`, `storeFile` keys).
- Produces: an updated `gh-pages` branch containing `repo/*.apk` and
  `repo/index-v1.json` / `index-v2.json`, which Task 6's GitHub Pages
  config serves publicly.

- [ ] **Step 1: Write the workflow file**

```yaml
name: Release

on:
  push:
    branches:
      - main

jobs:
  publish-fdroid-repo:
    name: Build, sign, and publish to the self-hosted F-Droid repo
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Install dependencies
        run: flutter pub get

      - name: Decode app signing keystore
        env:
          ANDROID_KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
        run: |
          echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > android/app/app-release.keystore

      - name: Write key.properties
        env:
          ANDROID_KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
          ANDROID_KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
          ANDROID_STORE_PASSWORD: ${{ secrets.ANDROID_STORE_PASSWORD }}
        run: |
          cat > android/key.properties <<EOF
          storePassword=${ANDROID_STORE_PASSWORD}
          keyPassword=${ANDROID_KEY_PASSWORD}
          keyAlias=${ANDROID_KEY_ALIAS}
          storeFile=app-release.keystore
          EOF

      - name: Build signed release APK
        run: flutter build apk --release --build-number="$GITHUB_RUN_NUMBER"

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
          path: fdroid-repo
          fetch-depth: 0

      - name: Decode repo signing keystore
        env:
          FDROID_KEYSTORE_BASE64: ${{ secrets.FDROID_KEYSTORE_BASE64 }}
        run: |
          echo "$FDROID_KEYSTORE_BASE64" | base64 -d > fdroid-repo/keystore.p12

      - name: Write fdroidserver config.yml
        working-directory: fdroid-repo
        env:
          FDROID_KEYSTORE_PASSWORD: ${{ secrets.FDROID_KEYSTORE_PASSWORD }}
        run: |
          cat > config.yml <<EOF
          repo_url: "https://d-rk.github.io/solitaire/repo"
          repo_name: "d-rk's Solitaire repo"
          repo_description: "Self-hosted F-Droid repo for the Solitaire app, published automatically from GitHub Actions."
          repo_keyalias: "repokey"
          keystore: "keystore.p12"
          keystorepass: "${FDROID_KEYSTORE_PASSWORD}"
          keypass: "${FDROID_KEYSTORE_PASSWORD}"
          EOF

      - name: Copy the new APK into the repo
        run: |
          mkdir -p fdroid-repo/repo
          cp build/app/outputs/flutter-apk/app-release.apk \
            "fdroid-repo/repo/solitaire-${GITHUB_RUN_NUMBER}.apk"

      - name: Regenerate the F-Droid repo index
        working-directory: fdroid-repo
        run: fdroid update --create-metadata

      - name: Publish updated repo to gh-pages
        uses: peaceiris/actions-gh-pages@v4
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: fdroid-repo
          publish_branch: gh-pages
          keep_files: true
          exclude_assets: 'keystore.p12,config.yml'
```

Notes on two details baked into this step:

- `exclude_assets` on the publish step stops the just-decoded
  `keystore.p12` and the `config.yml` (which embeds the plaintext repo
  keystore password) from ever being committed to the public `gh-pages`
  branch — only `repo/` and the generated index/metadata files are
  published.
- The APK filename includes `$GITHUB_RUN_NUMBER` so successive releases
  don't overwrite each other in `repo/`, matching the spec's requirement
  that `fdroid update` sees every historical APK.

- [ ] **Step 2: Validate the YAML syntax**

```bash
python3 -c "import yaml, sys; yaml.safe_load(open('.github/workflows/release.yml'))" && echo "valid YAML"
```

Expected: `valid YAML`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "Add release workflow: build, sign, and publish to self-hosted F-Droid repo"
```

---

### Task 6: Create the `gh-pages` branch and enable GitHub Pages

The workflow from Task 5 pushes to a `gh-pages` branch that doesn't exist
yet, and GitHub Pages needs to be told to serve it. **Confirm with the user
before running Step 2** — it makes the branch's contents (the F-Droid repo)
publicly reachable, which was accepted in brainstorming as "unlisted public
URL" but is worth a final explicit go-ahead since it's an irreversible
visibility change on their repo.

**Interfaces:**
- Produces: an empty `gh-pages` branch for Task 5's workflow to publish
  into on its first run, and a live Pages URL
  (`https://d-rk.github.io/solitaire/`) that Task 7 depends on.

- [ ] **Step 1: Create an empty `gh-pages` branch**

```bash
git checkout --orphan gh-pages
git rm -rf .
git commit --allow-empty -m "Initialize empty gh-pages branch for F-Droid repo"
git push origin gh-pages
git checkout main
```

- [ ] **Step 2: Enable GitHub Pages, served from `gh-pages` — confirm with the user first**

```bash
gh api repos/d-rk/solitaire/pages -X POST \
  -f "source[branch]=gh-pages" -f "source[path]=/"
```

- [ ] **Step 3: Verify Pages is enabled**

```bash
gh api repos/d-rk/solitaire/pages
```

Expected: JSON response with `"status"` moving from `"building"` to
`"built"` within a couple of minutes, and `"html_url":
"https://d-rk.github.io/solitaire/"`.

No commit needed on `main` for this task.

---

### Task 7: End-to-end verification — push, watch the workflow, confirm on the phone

**Interfaces:**
- Consumes: everything from Tasks 1–6.
- Produces: nothing further downstream — this is the final verification task from the spec.

- [ ] **Step 1: Push a real commit to `main` and watch the release workflow**

```bash
git push origin main
gh run watch --repo d-rk/solitaire
```

Expected: the `Release` workflow run completes with a green checkmark.

- [ ] **Step 2: Confirm the repo index was published**

```bash
curl -s https://d-rk.github.io/solitaire/repo/index-v1.json | python3 -m json.tool | head -20
```

Expected: valid JSON containing a `"repo"` object and an `"apps"` array
with one entry for `io.github.d_rk.solitaire`.

- [ ] **Step 3: Add the repo to F-Droid on the phone (one-time, manual)**

In the F-Droid app: Settings → Repositories → the `+` button → enter
`https://d-rk.github.io/solitaire/repo` as the repo URL. F-Droid will
fetch the index and display the fingerprint derived from the repo signing
key — accept it. The Solitaire app should now appear in F-Droid's
available-apps list; install it from there once to establish it as an
F-Droid-managed install (a build previously sideloaded outside F-Droid
won't be recognized as updatable by this repo, since Android tracks
install provenance).

- [ ] **Step 4: Confirm the update flow works**

Make any small change to the repo (or simply re-run the release workflow),
push to `main`, wait for the workflow to go green, then in F-Droid tap the
refresh/sync action (or wait for its periodic background check). Confirm
the Solitaire entry shows an "Update" button and that tapping it installs
the new version successfully.

- [ ] **Step 5: Commit (if Step 1 required a throwaway change to trigger the push)**

Only needed if an artificial change was made in Step 1 purely to trigger
the workflow — otherwise this task has no commit of its own; it verifies
Tasks 1–6.
