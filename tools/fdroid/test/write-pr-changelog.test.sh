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
