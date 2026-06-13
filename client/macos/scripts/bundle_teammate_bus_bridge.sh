#!/bin/sh
set -e

# Compile teammate_bus_bridge into the app bundle (next to TeamPilot) as a universal
# binary when possible so Intel + Apple Silicon builds both work. BusBridgeLocator
# looks for it via Platform.resolvedExecutable.parent.

BRIDGE_SRC="${SRCROOT}/../../tools/teammate_bus_bridge"
DART="${FLUTTER_ROOT}/bin/dart"
OUT="${BUILT_PRODUCTS_DIR}/${EXECUTABLE_FOLDER_PATH}/teammate_bus_bridge"
OUT_DIR="$(dirname "${OUT}")"
BRIDGE_ENTRY="${BRIDGE_SRC}/bin/teammate_bus_bridge.dart"

if [ ! -x "${DART}" ] || [ ! -f "${BRIDGE_ENTRY}" ]; then
  echo "warning: dart or bridge source missing; teammate_bus_bridge not bundled (claude team-bus falls back to HTTP)"
  exit 0
fi

mkdir -p "${OUT_DIR}"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

# Return space-separated arch list from a Mach-O binary (e.g. "arm64" or "x86_64 arm64").
read_arches() {
  lipo -info "$1" 2>/dev/null | sed -E 's/.*are: //;s/.*architecture: //'
}

compile_slice() {
  arch="$1"
  output="$2"
  "${DART}" compile exe "${BRIDGE_ENTRY}" \
    --target-os=macos \
    --target-arch="${arch}" \
    -o "${output}"
}

NATIVE_ARCH="$(uname -m)"
ARM64_OUT="${TMPDIR}/teammate_bus_bridge_arm64"
X64_OUT="${TMPDIR}/teammate_bus_bridge_x64"

case "${NATIVE_ARCH}" in
  arm64)
    compile_slice arm64 "${ARM64_OUT}"
    if compile_slice x64 "${X64_OUT}" 2>/dev/null; then
      ARM64_ARCHES="$(read_arches "${ARM64_OUT}")"
      X64_ARCHES="$(read_arches "${X64_OUT}")"
      if [ "${ARM64_ARCHES}" != "${X64_ARCHES}" ]; then
        lipo -create -output "${OUT}" "${ARM64_OUT}" "${X64_OUT}"
        echo "Bundled universal teammate_bus_bridge (${ARM64_ARCHES} + ${X64_ARCHES})"
      else
        cp "${ARM64_OUT}" "${OUT}"
        echo "warning: x64 cross-compile produced same arch (${ARM64_ARCHES}); bundled arm64-only teammate_bus_bridge"
      fi
    else
      cp "${ARM64_OUT}" "${OUT}"
      echo "warning: x64 slice build failed; bundled arm64-only teammate_bus_bridge"
    fi
    ;;
  x86_64)
    compile_slice x64 "${X64_OUT}"
    cp "${X64_OUT}" "${OUT}"
    echo "Bundled x86_64 teammate_bus_bridge"
    ;;
  *)
    "${DART}" compile exe "${BRIDGE_ENTRY}" -o "${OUT}"
    echo "Bundled ${NATIVE_ARCH} teammate_bus_bridge (default target)"
    ;;
esac

chmod +x "${OUT}"
