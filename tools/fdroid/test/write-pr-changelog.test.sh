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

# CRLF body (GitHub sends CRLF): CRs stripped, first paragraph only.
bash "$script" "$logs" 44 "Title" $'Intro line.\r\nmore.\r\n\r\nSecond para.'
got3="$(cat "$logs/44.txt")"
expected3=$'Title\n\nIntro line.\nmore.'
[ "$got3" = "$expected3" ] || { echo "FAIL crlf: got [$got3]"; exit 1; }

# Leading blank line: trimmed, no extra blank line in output.
bash "$script" "$logs" 45 "Title" $'\nActual.\nline2.\n\nSecond.'
got4="$(cat "$logs/45.txt")"
expected4=$'Title\n\nActual.\nline2.'
[ "$got4" = "$expected4" ] || { echo "FAIL leading-blank: got [$got4]"; exit 1; }

# Large body (>64KB) with a short first paragraph: must exit 0, no SIGPIPE.
big_tail="$(head -c 100000 /dev/zero | tr '\0' x)"
big_body="$(printf 'Short intro.\n\n%s' "$big_tail")"
bash "$script" "$logs" 46 "Big" "$big_body"
big_rc=$?
[ "$big_rc" -eq 0 ] || { echo "FAIL large-exit: rc=$big_rc"; exit 1; }
got5="$(cat "$logs/46.txt")"
expected5=$'Big\n\nShort intro.'
[ "$got5" = "$expected5" ] || { echo "FAIL large: got [$got5]"; exit 1; }

# versionCode guard: "../evil" must exit non-zero and write no file.
parent_evil="$work/evil.txt"
set +e
bash "$script" "$logs" "../evil" "Title" "Body." 2>/dev/null
guard_rc=$?
set -e
[ "$guard_rc" -ne 0 ] || { echo "FAIL guard-exit: expected non-zero"; exit 1; }
[ ! -e "$parent_evil" ] || { echo "FAIL guard-file: $parent_evil exists"; exit 1; }

echo "PASS"
