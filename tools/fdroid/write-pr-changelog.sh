#!/usr/bin/env bash
# Write an F-Droid per-version changelog: PR title, then (if present) a blank
# line and the first paragraph of the PR body.
set -euo pipefail

changelogs_dir="${1:?usage: write-pr-changelog.sh <changelogs_dir> <versionCode> <pr_title> <pr_body>}"
version_code="${2:?missing <versionCode>}"
pr_title="${3:?missing <pr_title>}"
pr_body="${4-}"

# Guard versionCode before writing anything, so a value like "../evil" can
# never escape changelogs_dir.
if ! [[ "$version_code" =~ ^[0-9]+$ ]]; then
  printf 'error: versionCode must be a positive integer, got: %s\n' \
    "$version_code" >&2
  exit 1
fi

mkdir -p "$changelogs_dir"
out="$changelogs_dir/$version_code.txt"

# GitHub PR bodies arrive CRLF-terminated; strip all carriage returns so the
# paragraph boundary is a plain blank line.
body="${pr_body//$'\r'/}"

# First paragraph = from the first non-blank line up to (but not including) the
# next blank line, with trailing whitespace stripped and leading blank lines
# skipped. A here-string (not a live pipe writer) feeds awk, so a large body
# with a short first paragraph never leaves a writer blocked on a closed pipe
# (no SIGPIPE under `set -o pipefail`).
first_para="$(
  awk '
    { sub(/[[:space:]]+$/, "") }
    /^$/ { if (started) exit; else next }
    { started = 1; print }
  ' <<< "$body"
)"

if [ -n "$first_para" ]; then
  printf '%s\n\n%s\n' "$pr_title" "$first_para" > "$out"
else
  printf '%s\n' "$pr_title" > "$out"
fi
