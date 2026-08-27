#!/usr/bin/env bash
# Verify that this app's release APK build is reproducible: build the SAME
# commit TWICE, in two independent, freshly-created Docker containers (root
# inside, so paths matching F-Droid/GitHub Actions conventions can be created
# without needing host sudo), and diff the resulting libapp.so.
#
# Why this exists: a Dart AOT snapshot embeds the absolute filesystem path of
# the app source root it was compiled from. Two builds only produce a
# byte-identical libapp.so if they build from the *same* absolute path. This
# script proves — or disproves — that this recipe's build is reproducible,
# without needing another GitHub Actions run or F-Droid buildserver cycle to
# find out. See docs/fdroid-reproducible-builds.md for the full story.
#
# Each container:
#   1. Clones this repo (from a read-only bind mount, no network needed) at
#      the given commit into /home/runner/work/<repo>/<repo> — GitHub
#      Actions' own default checkout path, which is also what F-Droid's real
#      buildserver recipe must move its checkout to (via a `sudo:` mkdir,
#      since only root can create /home/runner there — root inside a
#      container needs no such workaround).
#   2. Fetches the exact pinned Flutter version fresh (never reused between
#      runs, so a stale/mutated SDK checkout can't quietly explain a match).
#   3. Builds the given ABI with the exact flags the fdroiddata recipe and
#      release-apks.yml use.
#   4. Extracts and hashes lib/<abi>/libapp.so.
#
# Usage:
#   tools/fdroid/verify-reproducible-build.sh [commit] [abi] [flutter-version]
#
#   commit           default: HEAD
#   abi              default: arm64-v8a  (armeabi-v7a | arm64-v8a | x86_64)
#   flutter-version  default: 3.38.5 — must match pubspec.yaml's `flutter:` pin
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
COMMIT="${1:-HEAD}"
ABI="${2:-arm64-v8a}"
FLUTTER_VERSION="${3:-3.38.5}"

case "$ABI" in
  armeabi-v7a) TARGET_PLATFORM=android-arm ;;
  arm64-v8a)   TARGET_PLATFORM=android-arm64 ;;
  x86_64)      TARGET_PLATFORM=android-x64 ;;
  *) echo "error: unknown ABI '$ABI' (expected armeabi-v7a|arm64-v8a|x86_64)" >&2; exit 1 ;;
esac

RESOLVED_COMMIT="$(git -C "$REPO" rev-parse "$COMMIT")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "verifying reproducibility of commit $RESOLVED_COMMIT, ABI $ABI, flutter $FLUTTER_VERSION"
echo "(two independent containers; this downloads Flutter fresh in each — a few minutes each)"

# The in-container build script. GH Actions' default checkout path for repo
# "open-patience" is /home/runner/work/open-patience/open-patience — the same
# absolute path F-Droid's own buildserver recipe must relocate its checkout
# to, so both sides embed the same path in the AOT snapshot.
read -r -d '' BUILD_SCRIPT <<'EOS' || true
set -euo pipefail
commit="$1"
abi="$2"
target_platform="$3"
flutter_version="$4"

apt-get update -qq
apt-get install -y -qq --no-install-recommends git curl unzip xz-utils openjdk-17-jdk-headless ca-certificates >/dev/null

export ANDROID_HOME=/opt/android/sdk
export ANDROID_SDK_ROOT=/opt/android/sdk
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"

git config --global --add safe.directory /mnt/repo.git
mkdir -p /home/runner/work/open-patience
git clone -q /mnt/repo.git /home/runner/work/open-patience/open-patience
cd /home/runner/work/open-patience/open-patience
git checkout -q "$commit"

git clone -q --branch "$flutter_version" --depth 1 https://github.com/flutter/flutter.git /flutter-sdk
export PATH="/flutter-sdk/bin:$PATH"
export PUB_CACHE="$(pwd)/.pub-cache"
flutter config --no-analytics >/dev/null
flutter pub get --enforce-lockfile

export SOURCE_DATE_EPOCH=0
flutter build apk --release --flavor production --split-per-abi \
  --target-platform="$target_platform" --obfuscate \
  --split-debug-info=build/app/outputs/symbols

apk="build/app/outputs/flutter-apk/app-${abi}-production-release.apk"
unzip -p "$apk" "lib/${abi}/libapp.so" | sha256sum | awk '{print $1}' > /mnt/out/hash.txt
cp "$apk" "/mnt/out/app-${abi}-production-release.apk"
echo "container build done: $(cat /mnt/out/hash.txt)"
EOS

run_one() {
  local label="$1" outdir="$2"
  mkdir -p "$outdir"
  echo "--- container $label ---"
  docker run --rm \
    -v "$REPO/.git:/mnt/repo.git:ro" \
    -v "/opt/android/sdk:/opt/android/sdk:ro" \
    -v "$outdir:/mnt/out" \
    ubuntu:24.04 \
    bash -c "$BUILD_SCRIPT" bash "$RESOLVED_COMMIT" "$ABI" "$TARGET_PLATFORM" "$FLUTTER_VERSION"
}

run_one A "$WORK/a"
run_one B "$WORK/b"

hash_a="$(cat "$WORK/a/hash.txt")"
hash_b="$(cat "$WORK/b/hash.txt")"

echo ""
echo "libapp.so (lib/$ABI) sha256:"
echo "  container A: $hash_a"
echo "  container B: $hash_b"

if [ "$hash_a" = "$hash_b" ]; then
  echo "MATCH — build is reproducible for this commit/ABI/flutter-version."
  exit 0
else
  echo "MISMATCH — build is NOT reproducible for this commit/ABI/flutter-version."
  exit 1
fi
