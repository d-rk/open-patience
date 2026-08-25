#!/usr/bin/env bash
# Tests for `release.sh --verify-only`: it regenerates every asset and reports
# whether any committed output is stale, WITHOUT prompting, bumping, committing,
# tagging, or requiring a remote. Generators are stubbed; a fake `blender` is
# put on PATH so the Blender branch is exercised without a real install.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../release.sh"

fail() { echo "FAIL: $1"; exit 1; }

make_repo() {  # echoes a fresh repo path with stub generators, committed clean
  local repo bin
  repo="$(mktemp -d)"
  git init -q -b main "$repo"
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name Tester
  git -C "$repo" config commit.gpgsign false
  printf 'name: open_patience\nversion: 1.0.0+1\n' > "$repo/pubspec.yaml"
  mkdir -p "$repo/tools/logo" "$repo/tools/fdroid" "$repo/tools/art" \
           "$repo/metadata/en-US/images"
  # No-op generators (exit 0, touch nothing).
  : > "$repo/tools/logo/build_logo.py"
  : > "$repo/tools/art/build_art.py"
  : > "$repo/tools/fdroid/capture_screenshots.py"
  : > "$repo/tools/fdroid/build_feature_graphic.py"
  printf 'orig\n' > "$repo/metadata/en-US/images/featureGraphic.png"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init
  echo "$repo"
}

fake_blender_dir() {  # echoes a dir containing a no-op `blender` on PATH
  local bin="$1"
  mkdir -p "$bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/blender"
  chmod +x "$bin/blender"
}

# --- Scenario 1: assets up to date -> exit 0, no commit, no tag ---
repo1="$(make_repo)"
bin1="$repo1/.fakebin"; fake_blender_dir "$bin1"
before="$(git -C "$repo1" rev-parse HEAD)"

set +e
( cd "$repo1" && PATH="$bin1:$PATH" bash "$script" --verify-only )
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "verify-only exit $rc on clean assets (expected 0)"
[ "$(git -C "$repo1" rev-parse HEAD)" = "$before" ] || fail "verify-only created a commit"
[ -z "$(git -C "$repo1" tag -l)" ] || fail "verify-only created a tag"
rm -rf "$repo1"

# --- Scenario 2: a generator changes a tracked file -> nonzero exit ---
repo2="$(make_repo)"
bin2="$repo2/.fakebin"; fake_blender_dir "$bin2"
# Make the feature-graphic generator produce different bytes than committed.
cat > "$repo2/tools/fdroid/build_feature_graphic.py" <<'PY'
import os
here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(here, os.pardir, os.pardir,
                   "metadata", "en-US", "images", "featureGraphic.png")
open(out, "w").write("regenerated-different\n")
PY

set +e
( cd "$repo2" && PATH="$bin2:$PATH" bash "$script" --verify-only )
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "verify-only exit 0 on stale asset (expected nonzero)"
rm -rf "$repo2"

echo "PASS"
