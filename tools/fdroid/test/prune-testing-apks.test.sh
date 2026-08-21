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
