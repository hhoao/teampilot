#!/usr/bin/env bash
# Exercises release_channel.sh. Run from anywhere.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
script="$root/release_channel.sh"
fail=0

expect() {
  local name="$1"
  local want="$2"
  shift 2
  local got err status
  set +e
  got=$(env "$@" bash "$script" 2>"$root/.release_channel_test.err")
  status=$?
  set -e
  err="$(cat "$root/.release_channel_test.err")"
  if [ "$status" -ne 0 ]; then
    got="EXIT:${status}"$'\n'"${err%$'\n'}"
  else
    got="${got%$'\n'}"
  fi
  if [ "$got" = "$want" ]; then
    echo "ok  $name"
  else
    echo "FAIL $name" >&2
    printf '  want: %q\n' "$want" >&2
    printf '  got:  %q\n' "$got" >&2
    fail=1
  fi
}

expect "stable tag push stays latest" \
  $'tag=v4.0.0\nprerelease=false\nmake_latest=true\npublish=true' \
  RELEASE_EVENT=push \
  RELEASE_REF=refs/tags/v4.0.0 \
  RELEASE_REF_NAME=v4.0.0

expect "preview tag push is not latest" \
  $'tag=v4.0.0-preview.2\nprerelease=true\nmake_latest=false\npublish=true' \
  RELEASE_EVENT=push \
  RELEASE_REF=refs/tags/v4.0.0-preview.2 \
  RELEASE_REF_NAME=v4.0.0-preview.2

expect "dispatch on a branch does not publish" \
  $'tag=\nprerelease=false\nmake_latest=true\npublish=false' \
  RELEASE_EVENT=workflow_dispatch \
  RELEASE_REF=refs/heads/main \
  RELEASE_REF_NAME=main \
  RELEASE_INPUT_REF= \
  RELEASE_PREVIEW=false \
  PUBSPEC_VERSION=3.24.0

expect "preview of a branch still publishes" \
  $'tag=v4.0.0-preview.1\nprerelease=true\nmake_latest=false\npublish=true' \
  RELEASE_EVENT=workflow_dispatch \
  RELEASE_REF=refs/heads/main \
  RELEASE_REF_NAME=main \
  RELEASE_INPUT_REF=main \
  RELEASE_PREVIEW=true \
  PUBSPEC_VERSION=4.0.0 \
  TAGS=v3.24.0

expect "preview dispatch takes the next number" \
  $'tag=v3.24.0-preview.3\nprerelease=true\nmake_latest=false\npublish=true' \
  RELEASE_EVENT=workflow_dispatch \
  RELEASE_REF=refs/heads/main \
  RELEASE_REF_NAME=main \
  RELEASE_INPUT_REF= \
  RELEASE_PREVIEW=true \
  PUBSPEC_VERSION='3.24.0+55' \
  TAGS=$'v3.24.0\nv3.24.0-preview.1\nv3.24.0-preview.2\nv3.24.1-preview.9'

expect "pubspec prerelease uses that exact tag" \
  $'tag=v4.0.0-preview.1\nprerelease=true\nmake_latest=false\npublish=true' \
  RELEASE_EVENT=workflow_dispatch \
  RELEASE_REF=refs/heads/main \
  RELEASE_REF_NAME=main \
  RELEASE_INPUT_REF= \
  RELEASE_PREVIEW=true \
  PUBSPEC_VERSION=4.0.0-preview.1 \
  TAGS=$'v3.24.0\nv4.0.0-preview.2'

expect "auto-tag dispatch on a prerelease tag" \
  $'tag=v4.0.0-preview.1\nprerelease=true\nmake_latest=false\npublish=true' \
  RELEASE_EVENT=workflow_dispatch \
  RELEASE_REF=refs/tags/v4.0.0-preview.1 \
  RELEASE_REF_NAME=v4.0.0-preview.1 \
  RELEASE_INPUT_REF= \
  RELEASE_PREVIEW=false

expect "existing pubspec prerelease tag fails" \
  'EXIT:1
tag v4.0.0-preview.1 already exists. Bump the prerelease in client/pubspec.yaml.' \
  RELEASE_EVENT=workflow_dispatch \
  RELEASE_REF=refs/heads/main \
  RELEASE_REF_NAME=main \
  RELEASE_INPUT_REF= \
  RELEASE_PREVIEW=true \
  PUBSPEC_VERSION=4.0.0-preview.1 \
  TAGS=v4.0.0-preview.1

expect "preview flag on a stable tag fails" \
  'EXIT:1
ref v4.0.0 is a stable tag. Clear ref and enable preview to publish v4.0.0-preview.N.' \
  RELEASE_EVENT=workflow_dispatch \
  RELEASE_REF=refs/heads/main \
  RELEASE_REF_NAME=main \
  RELEASE_INPUT_REF=v4.0.0 \
  RELEASE_PREVIEW=true

rm -f "$root/.release_channel_test.err"
if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "all release channel checks passed"
