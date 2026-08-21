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
