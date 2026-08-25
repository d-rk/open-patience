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
mkdir -p "$repo/metadata/en-US" "$repo/metadata/de-DE"
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

# Both changelogs written, keyed by the new code.
[ -s "$repo/metadata/en-US/changelogs/8.txt" ] || fail "missing en-US changelog"
[ -s "$repo/metadata/de-DE/changelogs/8.txt" ] || fail "missing de-DE changelog"

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
