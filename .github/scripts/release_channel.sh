#!/usr/bin/env bash
# Decide whether a Release Packages run publishes, and whether that GitHub
# Release is a prerelease. Stable tags stay Latest. Preview tags do not.
set -euo pipefail

# RELEASE_EVENT       push | workflow_dispatch
# RELEASE_REF         full ref, such as refs/tags/v1.2.3 or refs/heads/main
# RELEASE_REF_NAME    v1.2.3 or main
# RELEASE_INPUT_REF   workflow_dispatch "ref" input; empty when unset
# RELEASE_PREVIEW     true | false | empty
# PUBSPEC_VERSION     client pubspec version, build metadata optional
# TAGS                existing tag names, one per line

semver_stable='^[0-9]+\.[0-9]+\.[0-9]+$'
semver_pre='^[0-9]+\.[0-9]+\.[0-9]+-[0-9A-Za-z.-]+$'
tag_stable='^v[0-9]+\.[0-9]+\.[0-9]+$'
tag_pre='^v[0-9]+\.[0-9]+\.[0-9]+-[0-9A-Za-z.-]+$'

emit() {
  echo "tag=$1"
  echo "prerelease=$2"
  echo "make_latest=$3"
  echo "publish=$4"
}

preview_requested() {
  [ "${RELEASE_PREVIEW:-}" = "true" ]
}

tag_exists() {
  local want="$1"
  local tag
  while IFS= read -r tag; do
    [ "$tag" = "$want" ] && return 0
  done <<< "${TAGS:-}"
  return 1
}

next_preview_tag() {
  local base="$1"
  local escaped="${base//./\\.}"
  local max=0
  local tag n
  while IFS= read -r tag; do
    [ -n "$tag" ] || continue
    if [[ "$tag" =~ ^v${escaped}-preview\.([0-9]+)$ ]]; then
      n="${BASH_REMATCH[1]}"
      if ((n > max)); then
        max=$n
      fi
    fi
  done <<< "${TAGS:-}"
  echo "v${base}-preview.$((max + 1))"
}

publish_tag() {
  local tag="$1"
  if [[ "$tag" =~ $tag_pre ]]; then
    emit "$tag" true false true
    return 0
  fi
  if [[ "$tag" =~ $tag_stable ]]; then
    if preview_requested; then
      echo "ref ${tag} is a stable tag. Clear ref and enable preview to publish v${tag#v}-preview.N." >&2
      exit 1
    fi
    emit "$tag" false true true
    return 0
  fi
  echo "unsupported release tag: $tag" >&2
  exit 1
}

publish_from_pubspec() {
  local version="${PUBSPEC_VERSION:-}"
  version="${version%%+*}"
  version="${version%"${version##*[![:space:]]}"}"
  version="${version#"${version%%[![:space:]]*}"}"
  local tag
  if [[ "$version" =~ $semver_pre ]]; then
    tag="v${version}"
    if tag_exists "$tag"; then
      echo "tag ${tag} already exists. Bump the prerelease in client/pubspec.yaml." >&2
      exit 1
    fi
    emit "$tag" true false true
    return 0
  fi
  if [[ "$version" =~ $semver_stable ]]; then
    emit "$(next_preview_tag "$version")" true false true
    return 0
  fi
  echo "pubspec version ${version:-<empty>} is not X.Y.Z or X.Y.Z-prerelease" >&2
  exit 1
}

event="${RELEASE_EVENT:-}"
if [ "$event" = "push" ]; then
  if [[ "${RELEASE_REF:-}" != refs/tags/* ]]; then
    emit "" false true false
    exit 0
  fi
  publish_tag "${RELEASE_REF_NAME:-}"
  exit 0
fi

if [ "$event" != "workflow_dispatch" ]; then
  echo "unsupported event: ${event:-<empty>}" >&2
  exit 1
fi

input="${RELEASE_INPUT_REF:-}"
if [[ "$input" =~ $tag_pre ]] || [[ "$input" =~ $tag_stable ]]; then
  publish_tag "$input"
  exit 0
fi

# Auto Tag dispatches the workflow on the new tag and leaves the ref input empty.
if [ -z "$input" ] && [[ "${RELEASE_REF:-}" == refs/tags/* ]]; then
  publish_tag "${RELEASE_REF_NAME:-}"
  exit 0
fi

if preview_requested; then
  publish_from_pubspec
  exit 0
fi

emit "" false true false
