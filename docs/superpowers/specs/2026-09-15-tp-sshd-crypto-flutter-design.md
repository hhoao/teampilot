# tp_sshd_crypto_flutter — Shim Bundling for App Builds (Design)

Date: 2026-09-15
Status: Approved (design phase)

## Problem

The Phase 1 FFI crypto work (branch `tp-sshd-differential-audit`, fork
`tp-sshd-ffi-crypto`) replaced the packet ciphers with a C shim over
libcrypto, and the loader now resolves it by bare soname first. But
**nothing puts the shim into an app bundle**: there is no `jniLibs` rule,
no iOS/macOS Frameworks phase, and no CMake install rule. The whole-branch
review made this Critical: in any packaged build the first SSH packet
throws the hard-dependency `StateError`. Every green gate so far ran from
a source checkout — exactly the configuration where the loader's
directory walk succeeds — so no gate could have caught it.

## Decision

Add one new Flutter FFI plugin package whose only responsibility is to
compile `dartssh2/native/tp_sshd_crypto.c` for each platform and let the
Flutter tool bundle the result:

```
client/packages/tp_sshd_crypto_flutter/
  pubspec.yaml          flutter.plugin.platforms.*.ffiPlugin: true
  linux/CMakeLists.txt  builds the shim, installs it into the bundle's lib/
  windows/CMakeLists.txt
  macos/*.podspec + CMakeLists
  android/build.gradle  externalNativeBuild -> CMakeLists.txt
  android/CMakeLists.txt
  README.md             what it is, why it exists, how to verify
```

The app gains one dependency line. `dartssh2` and `tp_sshd` stay **pure
Dart** — they keep loading by soname (already implemented), which the
bundled library now satisfies. Making `dartssh2` itself an `ffiPlugin`
was rejected: it would put the Flutter SDK in its pubspec and break
`dart test` for the pure-Dart `tp_sshd` package.

Rationale for a plugin package over hand-wiring the app's own build
files: the Flutter tool generates the platform build wiring
(`generated_plugins.cmake`, plugin gradle) automatically for
`ffiPlugin`s — the same mechanism `flutter_pty_new` uses in this repo —
so there is one mechanism to understand, it works for every platform
without per-app duplication, and it builds from source (no committed
per-ABI binaries to keep in sync for app builds; the committed prebuilts
remain for non-Flutter consumers and tests).

## Scope

In: Linux, macOS, Windows, Android. The repo has no `ios/` directory, so
iOS is out (documented as such).

Out: non-Flutter consumers' bundling, and any change to the FFI/cipher
code itself (Phase 1 is complete and reviewed).

## Acceptance

1. `cd client && flutter build linux --release` succeeds and the built
   bundle contains the shim (`lib/libtp_sshd_crypto.so`).
2. With the source-tree build artifact moved aside, the bundled app can
   load the shim — proven by a run/smoke that exercises the loader, not
   by inspection alone.
3. The fork and tp_sshd suites stay green (the plugin adds no Dart code
   to them).
4. macOS/Windows/Android lanes exist, are wired through the standard
   plugin mechanism, and are build-verified where the host toolchain
   allows; otherwise their verification is delegated to CI and the report
   says so explicitly.

## Risks / open questions

- **Android's libcrypto**: the NDK does not ship OpenSSL; Android ships
  BoringSSL as a platform library (`libcrypto.so`, linkable from API 28+)
  and BoringSSL provides the EVP APIs the shim uses (`EVP_chacha20`,
  `EVP_aes_{128,256}_gcm`) — the shim already avoids OpenSSL-3-only APIs
  (it vendors its own Poly1305 for exactly this reason). This must be
  verified by an actual Android link + symbol check, not assumed; if the
  platform lib proves insufficient the fallback is a vendored libcrypto
  for the Android ABIs, recorded as a follow-up.
- **Duplicated shim source**: the plugin's build files compile the shim
  *from the dartssh2 submodule's path*. If the shim's file layout changes,
  the plugin's build files break — a build-time failure, not a silent one.
- The `macos/` lane cannot be executed on this Linux host; its correctness
  rests on the standard plugin template and CI.
