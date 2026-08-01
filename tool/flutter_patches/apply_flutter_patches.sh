#!/usr/bin/env bash
# Apply TeamPilot Flutter SDK patches (idempotent).
#
# Drop new unified diffs as tool/flutter_patches/<name>.patch — no script/CI
# changes needed. Re-run safely after Flutter upgrades.
#
# Usage (from anywhere):
#   ./tool/flutter_patches/apply_flutter_patches.sh
#   FLUTTER_ROOT=/path/to/flutter ./tool/flutter_patches/apply_flutter_patches.sh
#
# Requires: flutter on PATH (or FLUTTER_ROOT), git.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PATCH_DIR="$SCRIPT_DIR"

if [[ -z "${FLUTTER_ROOT:-}" ]]; then
  if ! command -v flutter >/dev/null 2>&1; then
    echo "error: flutter not on PATH; set FLUTTER_ROOT" >&2
    exit 1
  fi
  # Prefer `flutter sdk-path` when available; else derive from the flutter binary.
  if FLUTTER_ROOT="$(flutter sdk-path 2>/dev/null)" && [[ -n "$FLUTTER_ROOT" ]]; then
    :
  else
    FLUTTER_BIN="$(command -v flutter)"
    # Resolve symlinks (e.g. asdf / fvm shims) when possible.
    if command -v readlink >/dev/null 2>&1; then
      FLUTTER_BIN="$(readlink -f "$FLUTTER_BIN" 2>/dev/null || readlink "$FLUTTER_BIN" || echo "$FLUTTER_BIN")"
    fi
    FLUTTER_ROOT="$(cd "$(dirname "$FLUTTER_BIN")/.." && pwd)"
  fi
fi

FLUTTER_ROOT="$(cd "$FLUTTER_ROOT" && pwd)"

if [[ ! -d "$FLUTTER_ROOT/packages/flutter/lib" ]]; then
  echo "error: not a Flutter SDK root: $FLUTTER_ROOT" >&2
  exit 1
fi

echo "Flutter SDK: $FLUTTER_ROOT"

shopt -s nullglob
# Stable order so multi-patch stacks apply deterministically.
mapfile -t patches < <(printf '%s\n' "$PATCH_DIR"/*.patch | LC_ALL=C sort)
if ((${#patches[@]} == 0)); then
  echo "error: no *.patch files in $PATCH_DIR" >&2
  exit 1
fi

applied=0
skipped=0
for patch in "${patches[@]}"; do
  name="$(basename "$patch")"

  # Reverse-check succeeds ⇒ tree already matches the patched result.
  if git -C "$FLUTTER_ROOT" apply --reverse --check --whitespace=nowarn "$patch" \
    >/dev/null 2>&1; then
    echo "skip $name (already applied)"
    skipped=$((skipped + 1))
    continue
  fi

  if ! git -C "$FLUTTER_ROOT" apply --check --whitespace=nowarn "$patch" \
    >/dev/null 2>&1; then
    echo "error: $name does not apply cleanly to $FLUTTER_ROOT" >&2
    echo "hint: Flutter stable drifted — refresh the patch from a matching SDK" >&2
    echo "      (see docs/flutter-patches.md)" >&2
    exit 1
  fi

  echo "apply $name"
  git -C "$FLUTTER_ROOT" apply --whitespace=nowarn "$patch"
  applied=$((applied + 1))
done

echo "flutter patches: applied=$applied skipped=$skipped (repo=$REPO_ROOT)"
