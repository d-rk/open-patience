#!/usr/bin/env bash
# Unit tests for the pure version/changelog helpers in release.sh. The script
# is source-safe: sourcing it defines the functions without running main().
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../release.sh
source "$here/../release.sh"

fail() { echo "FAIL: $1"; exit 1; }
eq() { [ "$1" = "$2" ] || fail "$3: expected [$2], got [$1]"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A representative pubspec: the version line among other keys we must preserve.
pubspec="$work/pubspec.yaml"
cat > "$pubspec" <<'EOF'
name: open_patience
description: A solitaire game.
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: ^3.5.0
EOF

# --- parsing ---
eq "$(parse_version_name "$pubspec")" "0.1.0" "parse_version_name"
eq "$(parse_version_code "$pubspec")" "1" "parse_version_code"
eq "$(next_version_code "$pubspec")" "2" "next_version_code"
eq "$(suggest_patch_bump "$pubspec")" "0.1.1" "suggest_patch_bump"

# --- semver validation ---
is_valid_semver "1.2.3"    || fail "is_valid_semver rejected 1.2.3"
is_valid_semver "10.0.42"  || fail "is_valid_semver rejected 10.0.42"
! is_valid_semver "1.2"     || fail "is_valid_semver accepted 1.2"
! is_valid_semver "1.2.3.4" || fail "is_valid_semver accepted 1.2.3.4"
! is_valid_semver "v1.2.3"  || fail "is_valid_semver accepted v1.2.3"
! is_valid_semver "1.2.x"   || fail "is_valid_semver accepted 1.2.x"

# --- rewriting the version line, preserving the rest of the file ---
write_pubspec_version "$pubspec" "0.2.0" "5"
eq "$(parse_version_name "$pubspec")" "0.2.0" "write_pubspec_version name"
eq "$(parse_version_code "$pubspec")" "5" "write_pubspec_version code"
grep -q '^name: open_patience$' "$pubspec" || fail "write clobbered name line"
grep -q '^  sdk: \^3.5.0$' "$pubspec" || fail "write clobbered environment block"
eq "$(grep -c '^version:' "$pubspec")" "1" "exactly one version line remains"

# --- changelog path derivation ---
eq "$(changelog_path /r en-US 5)" "/r/metadata/en-US/changelogs/5.txt" "changelog en"
eq "$(changelog_path /r de-DE 5)" "/r/metadata/de-DE/changelogs/5.txt" "changelog de"

echo "PASS"
