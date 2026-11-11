# tp_sshd_crypto_flutter

Flutter build wiring for the `tp_sshd_crypto` shim. This package exists so a
**packaged** app can load the shim at all: `dartssh2` opens
`libtp_sshd_crypto.so` / `libtp_sshd_crypto.dylib` / `tp_sshd_crypto.dll` by
bare file name, which the OS loader resolves out of the app bundle's library
directory. Nothing else in the tree puts a shim there — a release bundle built
before this package depended on the app contained no crypto shim, and
`NativeCrypto`'s first use threw its "not found" `StateError`.

## What it is (and is not)

- It is an FFI-only Flutter plugin: the `flutter: plugin:` block declares
  `ffiPlugin: true` for each platform, with no `pluginClass` and no
  `dartPluginClass`.
- It holds **no C of its own**. Every lane compiles
  `../dartssh2/native/tp_sshd_crypto.c` — the dartssh2 package's copy, which
  is the source of truth. A lane that needs an indirection (macOS/CocoaPods
  cannot take relative source paths) uses a forwarder that `#include`s it.
- It has **no Dart API**; `lib/tp_sshd_crypto_flutter.dart` is documentation
  only. The bindings are `dartssh2`'s
  (`lib/src/utils/native_crypto.dart`), and that is the only loader.

## Lanes

| Lane | Build file | Artifact | Status |
|------|-----------|----------|--------|
| Linux | `linux/CMakeLists.txt` | `libtp_sshd_crypto.so` | built from source by `flutter build linux`; **verified end-to-end** (see below) |
| Windows | `windows/CMakeLists.txt` | `tp_sshd_crypto.dll` | build wiring only; needs vcpkg OpenSSL (`OpenSSL::Crypto`), not verified on a Windows host |
| macOS | `macos/tp_sshd_crypto_flutter.podspec` + `macos/Classes/` | shim compiled into the plugin pod | build wiring only; not verified on a macOS host (see the caveat below) |
| Android | — | `libtp_sshd_crypto.so` | **not wired** — needs a vendored libcrypto first, see below |

The Linux and Windows lanes hand the Flutter tooling a
`tp_sshd_crypto_flutter_bundled_libraries` list (the FFI-plugin contract that
`linux/flutter/generated_plugins.cmake` expands); the app's
`linux/CMakeLists.txt` then installs every `PLUGIN_BUNDLED_LIBRARIES` entry
into `build/linux/<arch>/<mode>/bundle/lib/`.

### macOS caveat

The podspec compiles the shim, but CocoaPods produces a plugin framework named
after the pod (`use_frameworks!`), not a `libtp_sshd_crypto.dylib` on the
loader's search path. The macOS lane therefore still needs the dylib itself
placed in the bundle under the loader's name before a packaged macOS build can
load the shim; that has not been done or verified here (no macOS host). Do not
read the podspec's presence as a working macOS lane.

## Verifying the Linux bundle

```bash
cd client
flutter build linux --release
find build/linux -name 'libtp_sshd_crypto.so'   # → build/linux/x64/release/bundle/lib/libtp_sshd_crypto.so
```

To prove the *bundled* library is the one that loads, remove every shim from
the source tree, then launch with the bundle's `lib/` on the search path and
check which file the loader mapped (`/proc/self/maps`):

```bash
mv packages/dartssh2/native/libtp_sshd_crypto.so /tmp/
mv packages/dartssh2/native/prebuilt/linux/x64/libtp_sshd_crypto.so /tmp/
LD_LIBRARY_PATH=$PWD/build/linux/x64/release/bundle/lib \
  dart run --packages=$PWD/.dart_tool/package_config.json /tmp/tp_sshd_crypto_proof.dart
# encrypted=32 bytes, roundtrip=OK
# loaded from: /…/client/build/linux/x64/release/bundle/lib/libtp_sshd_crypto.so
```

Runtime floor: the Linux lane links the host's libcrypto, so the bundle needs
OpenSSL 3 (`native/prebuilt/README.md` documents the same floor for the
prebuilt matrix). A `dlopen` failure naming `libcrypto.so.3` is that
dependency missing, not the shim being absent.

## Android — vendored static libcrypto

The NDK ships **neither OpenSSL headers nor a linkable `libcrypto.so`** in its
sysroot (checked against the NDK 26.3 / 27.0 / 28.0 installs), so unlike the
desktop lanes this one cannot compile against the host's OpenSSL. It instead
compiles the shim against a **static libcrypto vendored per ABI** under
`android/vendor/<abi>/{lib/libcrypto.a,include/openssl/}`, which makes the
resulting `libtp_sshd_crypto.so` self-contained — the APK carries no separate
libcrypto and needs no runtime OpenSSL.

Vendored: `arm64-v8a` and `x86_64`, built from OpenSSL 3.5.5 with the NDK
(`android-arm64` / `android-x86_64`, `-D__ANDROID_API__=24 no-shared
no-tests no-apps`). `armeabi-v7a` is deliberately absent (32-bit ARM is
legacy here, and each vendored copy is ~11 MB): to add it, build the same
recipe for `android-arm` and add the ABI to `android/build.gradle`'s
`abiFilters`.

Recipe for a new ABI (also how to refresh the vendored version):

```bash
curl -sLO https://www.openssl.org/source/openssl-3.5.5.tar.gz && tar xzf openssl-3.5.5.tar.gz
cd openssl-3.5.5
export ANDROID_NDK_ROOT=$HOME/Android/Sdk/ndk/28.0.13004108
export PATH=$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH
./Configure android-arm64 -D__ANDROID_API__=24 no-shared no-tests no-apps --prefix=$PWD/out
make -j"$(nproc)" && make install_sw
# then copy out/lib/libcrypto.a and out/include/openssl into android/vendor/<abi>/
```

Refresh `libcrypto.a` and the headers together — a mismatched pair fails at
compile time, not silently. OpenSSL's licence
(`android/vendor/LICENSE.txt`) ships with the built artifacts.

**Verified** (NDK 28.0.13004108): `flutter build apk --release
--target-platform android-arm64` produces an APK containing
`lib/arm64-v8a/libtp_sshd_crypto.so` and `lib/x86_64/libtp_sshd_crypto.so`
(7 exported `tp_*` symbols each, ~5.3/5.7 MB, no separate libcrypto.so).

If the shim looks missing from a bundle you just built, `flutter clean` and
rebuild: an incremental build after this dependency was added has been observed
not to re-run the plugin's install step (the compiled artifact sits in
`build/<platform>/.../plugins/tp_sshd_crypto_flutter/` while the bundle's `lib/`
stays empty). It is a Flutter build-cache behavior, not a wiring bug.

Size note: static linking pulls ~5.8 MB of OpenSSL 3 per ABI into the APK
even though only three ciphers are used (the EVP provider machinery is
inseparable). A minimal-feature OpenSSL configuration is the lever if that
cost ever needs cutting.
