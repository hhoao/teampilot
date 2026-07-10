#!/usr/bin/env bash
#
# Re-vendor the pinned tree-sitter core + grammar sources into third_party/.
#
# The C sources are committed to the repo so that `flutter test` / `flutter
# build` work offline with no network or git-submodule dependency. Run this
# script only when bumping a pinned version; update third_party/README.md with
# the new tag + commit SHA afterwards.
#
# Usage: tool/fetch_grammars.sh
set -euo pipefail

# --- Pinned versions -------------------------------------------------------
# Keep these in sync with third_party/README.md.
TREE_SITTER_REPO="https://github.com/tree-sitter/tree-sitter.git"
TREE_SITTER_TAG="v0.25.10"

TREE_SITTER_JSON_REPO="https://github.com/tree-sitter/tree-sitter-json.git"
TREE_SITTER_JSON_TAG="v0.24.8"
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
THIRD_PARTY="$PKG_DIR/third_party"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

clone_tag() {
  local repo="$1" tag="$2" dest="$3"
  git clone --quiet --depth 1 --branch "$tag" "$repo" "$dest"
  echo "  $repo @ $tag -> $(git -C "$dest" rev-parse HEAD)"
}

echo "Fetching tree-sitter core..."
clone_tag "$TREE_SITTER_REPO" "$TREE_SITTER_TAG" "$WORK/tree-sitter"

echo "Fetching tree-sitter-json..."
clone_tag "$TREE_SITTER_JSON_REPO" "$TREE_SITTER_JSON_TAG" "$WORK/tree-sitter-json"

echo "Vendoring sources into third_party/ ..."
rm -rf \
  "$THIRD_PARTY/tree-sitter/lib" \
  "$THIRD_PARTY/tree-sitter-json/src"
mkdir -p \
  "$THIRD_PARTY/tree-sitter/lib/src" \
  "$THIRD_PARTY/tree-sitter/lib/include/tree_sitter" \
  "$THIRD_PARTY/tree-sitter-json/src"

# tree-sitter core: `lib/src` unity build (lib.c) + public include headers.
cp -r "$WORK/tree-sitter/lib/src/." "$THIRD_PARTY/tree-sitter/lib/src/"
cp "$WORK/tree-sitter/lib/include/tree_sitter/api.h" \
  "$THIRD_PARTY/tree-sitter/lib/include/tree_sitter/"
cp "$WORK/tree-sitter/LICENSE" "$THIRD_PARTY/tree-sitter/LICENSE"

# tree-sitter-json: generated parser + vendored parser ABI headers.
cp -r "$WORK/tree-sitter-json/src/." "$THIRD_PARTY/tree-sitter-json/src/"
cp "$WORK/tree-sitter-json/LICENSE" "$THIRD_PARTY/tree-sitter-json/LICENSE"

echo "Done. Review 'git diff third_party/' and update third_party/README.md."
