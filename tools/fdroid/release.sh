#!/usr/bin/env bash
# Cut a release: pick the new version, require both localized changelogs,
# verify every generated asset is up to date, bump pubspec, then commit, tag,
# and (on confirmation) push.
#
# pubspec.yaml is the single committed source of truth for the version
# (android/local.properties is gitignored and regenerated from it by the
# flutter tool; build.gradle.kts reads flutter.versionCode/Name). So a release
# rewrites exactly one line: `version: X.Y.Z+N`.
#
# The pure version/changelog helpers below are unit-tested in
# test/release.test.sh; this file is source-safe (sourcing defines the helpers
# without running main).
#
# Usage:
#   tools/fdroid/release.sh [--skip-verify]
#
#   --skip-verify  Skip regenerating and diff-checking assets. Use when the
#                  asset toolchain (Blender, Inkscape, Chrome, Flutter) is
#                  unavailable, or a generator's output is not byte-stable on
#                  this machine.
set -euo pipefail

# --------------------------------------------------------------------------
# Pure helpers (unit-tested). No I/O beyond the file paths handed to them.
# --------------------------------------------------------------------------

# Echo the versionName (X.Y.Z) from a pubspec's `version: X.Y.Z+N` line.
parse_version_name() {
  sed -n -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+.*/\1/p' "$1"
}

# Echo the versionCode (N) from a pubspec's `version: X.Y.Z+N` line.
parse_version_code() {
  sed -n -E 's/^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+).*/\1/p' "$1"
}

# Echo the next versionCode (current + 1).
next_version_code() {
  echo $(( $(parse_version_code "$1") + 1 ))
}

# Echo a patch-bumped versionName suggestion (X.Y.Z -> X.Y.(Z+1)).
suggest_patch_bump() {
  local name major rest minor patch
  name="$(parse_version_name "$1")"
  major="${name%%.*}"
  rest="${name#*.}"
  minor="${rest%%.*}"
  patch="${rest#*.}"
  echo "${major}.${minor}.$(( patch + 1 ))"
}

# Echo the per-ABI versionCodes for versionCode $2, space-separated. Releases
# ship one APK per ABI with versionCode = code*10 + abi; the abi numbers are
# read from the `abiCodes` map in the gradle file $1 (the single source of
# truth for the split), so the two can never drift. Fails if there is none.
abi_version_codes() {
  local gradle="$1" code="$2" abis abi
  [ -f "$gradle" ] || return 1
  abis="$(awk '/abiCodes[[:space:]]*=[[:space:]]*mapOf\(/ { on = 1 }
               on { print; if (index($0, ")")) exit }' "$gradle" \
    | grep -oE 'to[[:space:]]+[0-9]+' | grep -oE '[0-9]+')" || return 1
  local codes=()
  for abi in $abis; do
    codes+=("$(( code * 10 + abi ))")
  done
  echo "${codes[*]}"
}

# Succeed iff the argument is a strict X.Y.Z semver (no prefix, no suffix).
is_valid_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Rewrite the single `version:` line of a pubspec to `version: <name>+<code>`,
# leaving the rest of the file untouched.
write_pubspec_version() {
  local pubspec="$1" name="$2" code="$3" tmp
  tmp="$(mktemp)"
  sed -E "s/^version:.*/version: ${name}+${code}/" "$pubspec" > "$tmp"
  mv "$tmp" "$pubspec"
}

# Echo the F-Droid changelog path for a versionCode in a given locale.
changelog_path() {
  echo "$1/metadata/$2/changelogs/$3.txt"
}

# --------------------------------------------------------------------------
# Orchestration (interactive + git; exercised by hand, not the unit tests).
# --------------------------------------------------------------------------

LOCALES=(en-US de-DE)
GENERATORS_DESC="Blender art, app icon, feature graphic, store screenshots"

die() { printf 'error: %s\n' "$1" >&2; exit 1; }

# Fail unless the working tree is clean, we are on main, and not behind origin.
preflight() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "not inside a git repository"
  [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] \
    || die "releases are cut from main; check it out first"
  git diff --quiet && git diff --cached --quiet \
    || die "working tree has uncommitted changes; commit or stash first"
  git fetch --quiet origin main || die "could not fetch origin/main"
  if [ "$(git rev-list --count HEAD..origin/main)" -ne 0 ]; then
    die "local main is behind origin/main; pull first"
  fi
}

# Prompt for the new versionName, defaulting to a patch bump. Echoes it.
prompt_version_name() {
  local pubspec="$1" suggestion name
  suggestion="$(suggest_patch_bump "$pubspec")"
  while :; do
    read -r -p "New version name [$suggestion]: " name
    name="${name:-$suggestion}"
    is_valid_semver "$name" || { echo "  not a X.Y.Z version" >&2; continue; }
    if git rev-parse -q --verify "refs/tags/v$name" >/dev/null; then
      echo "  tag v$name already exists" >&2
      continue
    fi
    echo "$name"
    return 0
  done
}

# Write the release changelog for every locale. F-Droid reads one changelog
# per APK versionCode, so each locale's notes are authored once — opening
# $EDITOR on the first per-ABI file when it is missing or empty — then copied
# to the release's other per-ABI codes. The previous release's set ($2) is
# removed: only the latest release's notes are kept.
ensure_changelogs() {
  local repo="$1" cur_code="$2" code="$3" locale path primary c
  local editor="${EDITOR:-${VISUAL:-vi}}"
  local gradle="$repo/android/app/build.gradle.kts" codes cur_codes
  codes="$(abi_version_codes "$gradle" "$code")" \
    || die "no abiCodes map in $gradle; cannot derive per-ABI versionCodes"
  cur_codes="$(abi_version_codes "$gradle" "$cur_code")"
  for locale in "${LOCALES[@]}"; do
    primary="$(changelog_path "$repo" "$locale" "${codes%% *}")"
    if [ -s "$primary" ]; then
      echo "changelog present: $primary"
    else
      mkdir -p "$(dirname "$primary")"
      : > "$primary"
      echo "opening $editor to write the $locale changelog ($primary)…"
      "$editor" "$primary"
      [ -s "$primary" ] || die "changelog $primary is empty; aborting"
    fi
    for c in $codes; do
      path="$(changelog_path "$repo" "$locale" "$c")"
      [ "$path" = "$primary" ] || cp "$primary" "$path"
    done
    for c in $cur_codes; do
      rm -f "$(changelog_path "$repo" "$locale" "$c")"
    done
  done
}

# Run a generator, aborting with a clear hint if its toolchain is missing.
run_generator() {
  echo "  \$ $*"
  "$@" || die "generator failed: $*  (re-run with --skip-verify to bypass)"
}

# Regenerate every committed asset and abort if any tracked file changed —
# a diff means a generated asset was left stale relative to its source script.
verify_generated_assets() {
  local repo="$1" blender
  echo "verifying generated assets are up to date ($GENERATORS_DESC)…"
  run_generator python3 "$repo/tools/logo/build_logo.py"
  run_generator python3 "$repo/tools/fdroid/build_feature_graphic.py"
  if command -v blender >/dev/null 2>&1; then
    blender=(blender)
  elif command -v flatpak >/dev/null 2>&1 \
      && flatpak info org.blender.Blender >/dev/null 2>&1; then
    blender=(flatpak run org.blender.Blender)
  else
    die "Blender not found (needed to verify art; use --skip-verify to bypass)"
  fi
  run_generator "${blender[@]}" --background --python "$repo/tools/art/build_art.py"
  run_generator python3 "$repo/tools/fdroid/capture_screenshots.py"
  run_generator python3 "$repo/tools/fdroid/capture_screenshots.py" --tablet

  if ! git -C "$repo" diff --quiet; then
    echo "generated assets are out of date — these tracked files changed:" >&2
    git -C "$repo" --no-pager diff --stat >&2
    die "regenerate, commit the assets, then re-run (or use --skip-verify)"
  fi
  echo "  all generated assets are up to date."
}

main() {
  local skip_verify=0 verify_only=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --skip-verify) skip_verify=1 ;;
      --verify-only) verify_only=1 ;;
      *) die "unknown argument: $1 (usage: release.sh [--skip-verify|--verify-only])" ;;
    esac
    shift
  done
  if [ "$skip_verify" -eq 1 ] && [ "$verify_only" -eq 1 ]; then
    die "--skip-verify and --verify-only are mutually exclusive"
  fi

  local repo pubspec
  repo="$(git rev-parse --show-toplevel)"
  pubspec="$repo/pubspec.yaml"

  # --verify-only: just check the generated assets and stop. No preflight,
  # prompts, version bump, commit, tag, or remote — a standalone asset audit.
  if [ "$verify_only" -eq 1 ]; then
    verify_generated_assets "$repo"
    return 0
  fi

  preflight

  local cur_name cur_code code name
  cur_name="$(parse_version_name "$pubspec")"
  cur_code="$(parse_version_code "$pubspec")"
  code="$(next_version_code "$pubspec")"
  echo "current: $cur_name (code $cur_code)  ->  new code will be $code"
  name="$(prompt_version_name "$pubspec")"

  ensure_changelogs "$repo" "$cur_code" "$code"

  if [ "$skip_verify" -eq 1 ]; then
    echo "skipping asset verification (--skip-verify)."
  else
    verify_generated_assets "$repo"
  fi

  write_pubspec_version "$pubspec" "$name" "$code"
  echo "bumped pubspec to version: $name+$code"

  # -A on the changelog dirs also stages the previous release's removed set.
  local paths=("$pubspec")
  local locale
  for locale in "${LOCALES[@]}"; do
    paths+=("$repo/metadata/$locale/changelogs")
  done
  git -C "$repo" add -A -- "${paths[@]}"
  git -C "$repo" commit -m "chore(release): v$name (code $code)"
  git -C "$repo" tag -a "v$name" -m "Release v$name (code $code)"

  echo
  git -C "$repo" --no-pager show --stat HEAD
  echo
  local reply
  read -r -p "Push commit + tag v$name to origin/main? [y/N] " reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    git -C "$repo" push origin main --follow-tags
    echo "pushed. origin/main will publish the self-hosted repo; tag v$name is live."
  else
    echo "not pushed. To undo locally:"
    echo "  git -C \"$repo\" tag -d v$name && git -C \"$repo\" reset --hard HEAD~1"
  fi
}

# Only run main when executed directly, so tests can source the helpers.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
