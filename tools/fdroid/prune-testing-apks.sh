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
