#!/bin/sh
set -e

# Compile teammate_bus_bridge into the app bundle (next to TeamPilot) as a universal
# binary when possible so Intel + Apple Silicon builds both work. BusBridgeLocator
# looks for it via Platform.resolvedExecutable.parent.

BRIDGE_SRC="${SRCROOT}/../../tools/teammate_bus_bridge"
DART="${FLUTTER_ROOT}/bin/dart"
OUT="${BUILT_PRODUCTS_DIR}/${EXECUTABLE_FOLDER_PATH}/teammate_bus_bridge"
OUT_DIR="$(dirname "${OUT}")"

if [ ! -x "${DART}" ] || [ ! -f "${BRIDGE_SRC}/bin/teammate_bus_bridge.dart" ]; then
  echo "warning: dart or bridge source missing; teammate_bus_bridge not bundled (claude team-bus falls back to HTTP)"
  exit 0
fi

mkdir -p "${OUT_DIR}"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

NATIVE_ARCH="$(uname -m)"
NATIVE_OUT="${TMPDIR}/teammate_bus_bridge_${NATIVE_ARCH}"
"${DART}" compile exe "${BRIDGE_SRC}/bin/teammate_bus_bridge.dart" -o "${NATIVE_OUT}"

if [ "${NATIVE_ARCH}" = "arm64" ]; then
  OTHER_OUT="${TMPDIR}/teammate_bus_bridge_x86_64"
  if arch -x86_64 "${DART}" compile exe "${BRIDGE_SRC}/bin/teammate_bus_bridge.dart" -o "${OTHER_OUT}"; then
    lipo -create -output "${OUT}" "${NATIVE_OUT}" "${OTHER_OUT}"
    echo "Bundled universal teammate_bus_bridge (arm64 + x86_64)"
  else
    cp "${NATIVE_OUT}" "${OUT}"
    echo "warning: x86_64 slice build failed; bundled arm64-only teammate_bus_bridge"
  fi
elif [ "${NATIVE_ARCH}" = "x86_64" ]; then
  cp "${NATIVE_OUT}" "${OUT}"
  echo "Bundled x86_64 teammate_bus_bridge"
else
  cp "${NATIVE_OUT}" "${OUT}"
  echo "Bundled ${NATIVE_ARCH} teammate_bus_bridge"
fi

chmod +x "${OUT}"
