# tp_sshd_crypto_flutter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Flutter FFI plugin package that compiles the dartssh2 crypto shim per platform so the Flutter tool bundles it, closing the whole-branch review's Critical (packaged builds could not load the shim).

**Architecture:** A new pure-build package `client/packages/tp_sshd_crypto_flutter/` declares `ffiPlugin: true` per platform and its platform build files compile `packages/dartssh2/native/tp_sshd_crypto.c` into the app bundle. `dartssh2`/`tp_sshd` keep loading by bare soname (already implemented in Phase 1). The app adds one dependency line.

**Tech Stack:** Flutter plugin tooling (`generated_plugins.cmake` / plugin gradle), CMake, Android NDK, the Phase 1 C shim.

**Spec:** `docs/superpowers/specs/2026-09-15-tp-sshd-crypto-flutter-design.md`.

## Global Constraints

- `dartssh2` and `tp_sshd` MUST stay pure Dart: no `flutter:` section, no Flutter SDK dependency in their pubspecs. The new package is the ONLY place Flutter build tooling appears.
- The shim source is compiled FROM `../dartssh2/native/tp_sshd_crypto.c` (path dependency sibling) — never copied or duplicated into the new package.
- The in-repo reference for the plugin shape is `client/packages/flutter_pty_new/` (`android/build.gradle`, `android/src/.../CMakeLists.txt`, `linux/`, `windows/`, `macos/`, and its `pubspec.yaml`'s `flutter: plugin: platforms:` block with `ffiPlugin: true`). Follow its structure; deviate only where the shim's needs differ (notably the libcrypto link).
- Android links against the platform `libcrypto.so` (BoringSSL) — verified by a real NDK link + symbol check in Task 2, not assumed. If it proves insufficient, the fallback (vendored libcrypto for Android ABIs) is recorded as a follow-up, not implemented here.
- Gates: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` (0 errors) after wiring; the fork and tp_sshd suites must stay green (`dart test` in each) — the plugin adds no Dart code to them.
- Commits on the current branch (`tp-sshd-differential-audit`); trailer `Co-Authored-By: Claude <noreply@anthropic.com>`. NEVER push.

## File Structure

```
client/packages/tp_sshd_crypto_flutter/
  pubspec.yaml           [new] name/version/deps (dartssh2 path dep) + flutter.plugin.platforms.*.ffiPlugin
  README.md              [new] what it is, why, how to verify
  lib/tp_sshd_crypto_flutter.dart  [new] empty/sentinel library (Dart requires one; documents that the package ships no Dart API)
  linux/CMakeLists.txt   [new] compiles the shim, installs into the bundle
  windows/CMakeLists.txt [new]
  macos/                 [new] podspec + CMakeLists (the standard plugin template shape)
  android/build.gradle   [new] externalNativeBuild -> android/CMakeLists.txt
  android/CMakeLists.txt [new] NDK build of the shim
  android/src/main/AndroidManifest.xml [new] empty plugin manifest (the template shape)
client/pubspec.yaml      [mod] add the path dependency
client/linux/CMakeLists.txt, client/windows/CMakeLists.txt [mod only if the generated wiring requires it — verify first, the tool usually handles it]
docs/DEVELOPMENT.md      [mod] replace the "must not reach a release build" warning with the bundling note
```

---

### Task 1: Plugin package + desktop lanes (Linux verified end-to-end)

**Files:**
- Create: `client/packages/tp_sshd_crypto_flutter/{pubspec.yaml,README.md,lib/tp_sshd_crypto_flutter.dart}`
- Create: `client/packages/tp_sshd_crypto_flutter/{linux,windows,macos}/CMakeLists.txt` (+ macos podspec)
- Modify: `client/pubspec.yaml` (path dependency)

**Interfaces:**
- Consumes: `client/packages/dartssh2/native/tp_sshd_crypto.c` (+ .h and the `build.sh` for the local/test path); the loader's soname resolution (Phase 1, `dartssh2/lib/src/utils/native_crypto.dart`).
- Produces: a buildable Flutter plugin named `tp_sshd_crypto_flutter` whose Linux/windows/macos lanes install `libtp_sshd_crypto.so` / `.dylib` into the app bundle, and the app's `pubspec.yaml` depending on it.

- [ ] **Step 1: Read the reference.** `client/packages/flutter_pty_new/pubspec.yaml` (the `flutter: plugin:` block, especially `ffiPlugin: true` and the platforms map), `client/packages/flutter_pty_new/android/build.gradle` and its `android/src/*/CMakeLists.txt`, and whatever `linux/`/`windows/`/`macos/` files that package has. Copy the STRUCTURE, not the content.

- [ ] **Step 2: Write the pubspec.** Model it on flutter_pty_new's; the essential parts:

```yaml
name: tp_sshd_crypto_flutter
description: Bundles the tp_sshd crypto shim (dartssh2/native) into Flutter app builds.
version: 0.1.0
publish_to: none

environment:
  sdk: ">=3.0.0 <4.0.0"
  flutter: ">=3.0.0"

dependencies:
  flutter:
    sdk: flutter
  dartssh2:
    path: ../dartssh2

flutter:
  plugin:
    platforms:
      linux:
        ffiPlugin: true
      windows:
        ffiPlugin: true
      macos:
        ffiPlugin: true
      android:
        ffiPlugin: true
```

(Confirm the exact key names against flutter_pty_new's block and the Flutter tooling's expectations for an FFI-only plugin — a `ffiPlugin: true` platform entry with no `pluginClass` is the FFI-only shape. If the tool insists on a `dartPluginClass` for some platform, follow what flutter_pty_new does.)

- [ ] **Step 3: Write the Linux lane.** `linux/CMakeLists.txt`, modeled on flutter_pty_new's: a `add_library(tp_sshd_crypto SHARED <path-to>/tp_sshd_crypto.c)` with `-O2`, `target_link_libraries(... crypto)`, then `install(TARGETS tp_sshd_crypto LIBRARY DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)`. Determine `INSTALL_BUNDLE_LIB_DIR` the way flutter_pty_new's does (the Flutter-generated bundle layout). The shim path from this file is `${CMAKE_CURRENT_SOURCE_DIR}/../../dartssh2/native/tp_sshd_crypto.c`.

- [ ] **Step 4: Write the Windows lane** (same shape, `.dll`, link `libcrypto` from wherever the Windows story puts it — for now mirror flutter_pty_new's Windows lane and note the vcpkg/OpenSSL assumption in a comment) **and the macOS lane** (standard `.podspec` + CMakeLists producing `.dylib`, linked against the SDK's libcrypto).

- [ ] **Step 5: Add the app dependency** — `client/pubspec.yaml`, in the existing path-dependency block (alongside `packages/flutter_pty_new`, `packages/dartssh2`, `packages/tp_sshd`): `tp_sshd_crypto_flutter:\n    path: packages/tp_sshd_crypto_flutter`. Run `cd client && flutter pub get`.

- [ ] **Step 6: Verify the Linux bundle end-to-end (the acceptance test).**

```bash
cd client && flutter build linux --release 2>&1 | tail -5
find build/linux -name 'libtp_sshd_crypto.so'      # expect at least one hit under the bundle
ls build/linux/*/release/bundle/lib/               # confirm the shim is in the bundle's lib/
```

If the shim is absent, the plugin wiring is wrong — debug it here (check `build/linux/*/generated_plugins.cmake` lists the plugin and that its CMakeLists ran).

- [ ] **Step 7: Prove the bundled library is what loads.** With the source-tree artifact moved aside (`mv client/packages/dartssh2/native/libtp_sshd_crypto.so /tmp/`), run the app's Linux release binary with `LD_LIBRARY_PATH` pointing at the bundle's `lib/` and an env-var-free launch — the acceptance is that the loader's soname resolution finds it. Simplest concrete proof: run a tiny Dart entry (or the app) that constructs `OpenSSHChaCha20Poly1305` and encrypts once; document the exact command in the report. Restore the moved file afterwards.

- [ ] **Step 8: Gate + commit.** `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` (0 errors) and the two Dart suites (`cd packages/dartssh2 && dart test`, `cd packages/tp_sshd && dart test`) still green. Commit (one commit: the new package + the app dependency; note the bundle verification in the message).

---

### Task 2: Android lane + libcrypto verification

**Files:**
- Create: `client/packages/tp_sshd_crypto_flutter/android/{build.gradle,CMakeLists.txt,src/main/AndroidManifest.xml,settings.gradle if the template has one}`
- Modify: the plugin's README with the Android story

**Interfaces:**
- Consumes: Task 1's package + the NDK (`~/Android/Sdk/ndk/<ver>` is present; `ANDROID_HOME` is unset in this shell, so the implementer must locate the SDK root — try `~/Android/Sdk`, `local.properties` in `client/android/`, or the Flutter config).
- Produces: an Android lane that compiles the shim for the app's ABIs and links libcrypto, plus a written answer on whether Android's platform libcrypto suffices.

- [ ] **Step 1: Write the Android lane** mirroring flutter_pty_new's `android/build.gradle` (`android { externalNativeBuild { cmake { path "CMakeLists.txt" } } }` plus the plugin's `flutter { source = '../..' }`-style block if the template uses one) and `android/CMakeLists.txt` (`add_library(tp_sshd_crypto SHARED ../../../dartssh2/native/tp_sshd_crypto.c)`, `target_link_libraries(tp_sshd_crypto crypto)`).

- [ ] **Step 2: Verify the libcrypto question for real.** With the NDK's clang for `aarch64-linux-android<api>`, compile the shim and inspect the result:

```bash
NDK=~/Android/Sdk/ndk/28.0.13004108   # pick what exists
$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android28-clang \
  -O2 -shared -fPIC <shim.c> -o /tmp/shim-android.so -lcrypto
$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm -D /tmp/shim-android.so | grep ' U EVP_'
```

Expected: links and the undefined `EVP_*` symbols are the ones the platform `libcrypto.so` provides (`EVP_chacha20`, `EVP_aes_128_gcm`, `EVP_aes_256_gcm`, the `EVP_CIPHER_CTX_*` family, `CRYPTO_memcmp`, `OPENSSL_cleanse`). If the link fails or symbols are missing, record the exact failure and the fallback (vendored libcrypto per ABI) as a follow-up — do NOT vendor anything in this task.

- [ ] **Step 3: Build the APK if the toolchain resolves** (`cd client && flutter build apk --release --target-platform android-arm64`, after locating the SDK). Verify `unzip -l` on the APK's `lib/arm64-v8a/` contains `libtp_sshd_crypto.so`. If the Android SDK/toolchain cannot be resolved on this host, say so explicitly in the report and leave the lane CI-verified.

- [ ] **Step 4: Gate + commit.** Android manifest/build files + the README's Android section + the report's libcrypto finding.

---

### Task 3: Close the documentation gap + final verification

**Files:**
- Modify: `docs/DEVELOPMENT.md` (replace the "must not reach a release build" warning with the bundling note + the verification recipe)
- Modify: `client/packages/dartssh2/native/prebuilt/README.md` and the loader's doc comment if they still assert that nothing bundles the shim
- Modify: `client/packages/dartssh2/lib/src/utils/native_crypto.dart` doc comment (same assertion)
- (No Dart logic changes.)

**Interfaces:** consumes everything above; produces the corrected durable record.

- [ ] **Step 1: Update the three places that say "nothing bundles the shim".** They were true when written and are now false for Flutter app builds — say what IS now true: `tp_sshd_crypto_flutter` bundles it for Flutter apps on linux/windows/macos/android; non-Flutter consumers still need the prebuilt or a local build; iOS remains unwired (no `ios/` in this repo).

- [ ] **Step 2: Record the verification recipe** in DEVELOPMENT.md: the `flutter build linux --release` + bundle-inspection command, and the loader-smoke procedure from Task 1 Step 7, so a future reader can re-run the acceptance.

- [ ] **Step 3: Full verification + report.** `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`; `cd client/packages/dartssh2 && dart test`; `cd client/packages/tp_sshd && dart test`; re-run the Task 1 Step 6 bundle check on the final tree. Report the exact outputs.

- [ ] **Step 4: Commit.**

---

## Self-Review

**Spec coverage:** the plugin package + per-platform lanes (T1 desktop, T2 Android) = the spec's Decision/Scope; the libcrypto risk (spec Risks) = T2 Step 2 with the documented fallback; acceptance criteria 1–2 = T1 Steps 6–7, criterion 3 = T1 Step 8 / T3 Step 3, criterion 4 = T2 Step 3 (per-platform build verification delegated to CI where the host cannot); the "three places still claim nothing bundles it" cleanup = T3 Step 1 (found by reading the Phase 1 fix wave's own edits).

**Placeholder scan:** the plugin file contents are specified by reference to an in-repo working example (`flutter_pty_new`) plus the exact differing bits (the shim source path, the libcrypto link, the Dart no-op library); the pubspec is given in full; the verification commands are exact. No TBDs.

**Type consistency:** `tp_sshd_crypto_flutter` named identically everywhere; the shim path `../../dartssh2/native/tp_sshd_crypto.c` is the same relative location T1 Step 3 and T2 Step 1 use (verified against the current tree layout: `client/packages/{dartssh2,tp_sshd_crypto_flutter}` are siblings).
