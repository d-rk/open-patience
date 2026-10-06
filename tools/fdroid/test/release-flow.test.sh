#!/usr/bin/env bash
# End-to-end flow test for release.sh: drives a real (throwaway) git repo with
# a fake $EDITOR and scripted answers, declining the final push. Asserts the
# version bump, changelogs, commit, and tag — without ever pushing.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../release.sh"

fail() { echo "FAIL: $1"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

origin="$work/origin.git"
git init -q --bare -b main "$origin"

repo="$work/repo"
git init -q -b main "$repo"
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name Tester
git -C "$repo" config commit.gpgsign false

cat > "$repo/pubspec.yaml" <<'EOF'
name: open_patience
description: A solitaire game.
version: 1.2.3+7

environment:
  sdk: ^3.5.0
EOF
# The ABI split: each release ships one APK per ABI, versionCode = code*10+abi.
mkdir -p "$repo/android/app"
cat > "$repo/android/app/build.gradle.kts" <<'GRADLE'
val abiCodes = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)
GRADLE
# The previous release's per-ABI changelogs, plus the initial-release one.
for locale in en-US de-DE; do
  mkdir -p "$repo/metadata/$locale/changelogs"
  echo "Initial Release" > "$repo/metadata/$locale/changelogs/2.txt"
  for abi in 1 2 3; do
    echo "Old notes" > "$repo/metadata/$locale/changelogs/7$abi.txt"
  done
done
git -C "$repo" add -A
git -C "$repo" commit -qm "init"
git -C "$repo" remote add origin "$origin"
git -C "$repo" push -q -u origin main

# Fake editor: write deterministic notes into whichever file it is handed.
editor="$work/fake-editor.sh"
cat > "$editor" <<'EOS'
#!/usr/bin/env bash
printf 'Release notes for the test.\n' > "$1"
EOS
chmod +x "$editor"

# Answers: new version name, then decline the push. --skip-verify: this repo
# has no generator toolchain; asset verification is covered separately.
( cd "$repo" && printf '1.2.4\nn\n' | EDITOR="$editor" bash "$script" --skip-verify ) \
  || fail "release.sh exited non-zero"

# pubspec bumped: name from input, code auto-incremented 7 -> 8.
grep -q '^version: 1.2.4+8$' "$repo/pubspec.yaml" \
  || fail "pubspec not bumped to 1.2.4+8"

# Each locale's notes written once, then fanned out to every per-ABI code of
# the new release (8 -> 81/82/83); the previous release's set is replaced and
# the initial-release changelog is left alone.
for locale in en-US de-DE; do
  dir="$repo/metadata/$locale/changelogs"
  for abi in 1 2 3; do
    grep -qx 'Release notes for the test.' "$dir/8$abi.txt" \
      || fail "missing $locale changelog 8$abi"
    [ ! -e "$dir/7$abi.txt" ] || fail "previous $locale changelog 7$abi kept"
  done
  [ ! -e "$dir/8.txt" ] || fail "$locale changelog written under the bare code"
  [ -s "$dir/2.txt" ] || fail "initial $locale changelog removed"
done
# Everything the release touched is in the commit.
[ -z "$(git -C "$repo" status --porcelain)" ] \
  || fail "release left uncommitted changes: $(git -C "$repo" status --porcelain)"

# Commit + annotated tag created locally.
git -C "$repo" log -1 --pretty=%s | grep -q '^chore(release): v1.2.4 (code 8)$' \
  || fail "release commit subject wrong"
git -C "$repo" rev-parse -q --verify refs/tags/v1.2.4 >/dev/null \
  || fail "tag v1.2.4 not created"

# Push was declined: origin/main must still point at the initial commit.
init_rev="$(git -C "$repo" rev-parse HEAD~1)"
[ "$(git -C "$repo" rev-parse origin/main)" = "$init_rev" ] \
  || fail "push was not declined (origin/main moved)"

echo "PASS"
