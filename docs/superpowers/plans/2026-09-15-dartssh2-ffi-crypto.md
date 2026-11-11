# dartssh2 FFI Crypto Acceleration — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fork's pure-Dart ChaCha20-Poly1305 and AES-256-GCM packet ciphers with FFI calls into a C shim over libcrypto, lifting the cipher ceiling from ~40–58 MB/s to ≥500 MB/s and end-to-end SFTP throughput from ~36 MB/s to ≥80 MB/s.

**Architecture:** A ~200-line C shim (`native/tp_sshd_crypto.c` in the dartssh2 fork) wraps libcrypto's EVP interfaces for the two SSH cipher operations; a Dart FFI loader (`lib/src/utils/native_crypto.dart`) opens the library (hard dependency — throw on failure). The two existing cipher sites swap their internals to shim calls with unchanged public shapes: `OpenSSHChaCha20Poly1305` keeps its class interface, and `_processAead` keeps its signature. CI prebuilds ship in-repo (flutter_pty_new distribution model); test environments compile locally via `native/build.sh`.

**Tech Stack:** C (EVP API of OpenSSL/libcrypto), dart:ffi, Dart. CI: existing toolchain lanes.

**Spec:** `docs/superpowers/specs/2026-09-15-dartssh2-ffi-crypto-design.md`.

## Global Constraints

- Hard dependency: no pure-Dart fallback in any environment — a missing library is an immediate, descriptive error (naming the expected path and the `native/build.sh` remedy). The existing pure-Dart cipher code is REMOVED in the final task, not kept behind a flag.
- Both cipher public shapes are frozen: `OpenSSHChaCha20Poly1305.encryptPacket(Uint8List packet, int sequenceNumber) -> Uint8List` / `decryptPacket(...)` and `ssh_transport.dart`'s `_processAead({key, iv, sequence, aad, input, forEncryption}) -> Uint8List` keep their exact signatures — the transport layer must not change.
- The shim never allocates: caller-owned buffers in and out. Dart-side FFI calls allocate the output buffers before the call.
- All existing suites are the equivalence gate: tp_sshd 104+ tests and fork 712+ tests must stay green with FFI ciphers active (after `native/build.sh`).
- Known-answer tests (RFC 8439 chacha vectors, one OpenSSH packet vector, one NIST aes256-gcm vector) must pass through the shim — protocol round trips alone can mask a shared endianness/nonce bug.
- Bench acceptance: FFI chacha ≥ 500 MB/s on 32 KiB packets on the machine that measured 40–58 MB/s baseline; end-to-end SFTP ≥ 80 MB/s (if lower with a fast cipher, record the residual bottleneck as Phase 2 evidence — still acceptance-complete).
- Differential harness `dart run tool/differential/run_audit.dart --area all` must regenerate clean (protocol behavior unchanged).
- Work happens on branch `tp-sshd-ffi-crypto` (off `tp-sshd-differential-audit`'s successor state — the worktree's current branch), commits in BOTH repos: the fork (submodule, on branch `differential-fixes`, never pushed by agents) and the parent (gitlink bumps per fork change). Commit trailer: `Co-Authored-By: Claude <noreply@anthropic.com>`.
- Windows libcrypto: vendored OpenSSL via vcpkg in CI only — Phase 1's runtime gate is Linux; other platforms are build + KAT smoke (the app's packaging flows pick up the prebuilts later).

## File Structure

```
client/packages/dartssh2/
  native/
    tp_sshd_crypto.h          [new] shim public API (both cipher families)
    tp_sshd_crypto.c          [new] EVP-backed implementations
    build.sh                  [new] local/test build (cc -shared, both Linux+macOS)
  lib/src/utils/
    native_crypto.dart        [new] FFI bindings + hard loader (NativeCrypto class)
  lib/src/utils/
    openssh_chacha20_poly1305.dart  [mod] internals -> NativeCrypto (class shape frozen)
  lib/src/ssh_transport.dart        [mod] _processAead -> NativeCrypto (signature frozen)
  test/src/
    native_crypto_kat_test.dart     [new] known-answer tests through the shim
client/packages/tp_sshd/
  example/bench_cipher.dart         [mod] bench both implementations, report MB/s
client/packages/dartssh2/.gitignore [mod] ignore locally built .so artifacts
```

---

### Task 1: C shim + local build script

**Files:**
- Create: `client/packages/dartssh2/native/tp_sshd_crypto.h`
- Create: `client/packages/dartssh2/native/tp_sshd_crypto.c`
- Create: `client/packages/dartssh2/native/build.sh` (executable)
- Modify: `client/packages/dartssh2/.gitignore` (locally built artifacts)

**Interfaces:**
- Consumes: system libcrypto EVP API (`<openssl/evp.h>`).
- Produces (the C ABI Tasks 2–3 bind to — exact):

```c
// OpenSSH EtM chacha20-poly1305 (PROTOCOL.chacha20poly1305):
// key is 64 bytes: K_1 (payload, bytes 0..31) and K_2 (length, bytes 32..63).
// nonce is 12 bytes: 4 zero bytes + sequence number big-endian (the OpenSSH
// construction; the Dart side builds it today — the shim takes it pre-built).
// Encrypts pkt in place is NOT offered: out must be caller-owned and
// >= in_len + 16 (tag appended). Returns 0 on success.
int tp_chacha20poly1305_encrypt(
    const uint8_t key[64], const uint8_t nonce[12],
    const uint8_t *aad, size_t aad_len,
    const uint8_t *plaintext, size_t plaintext_len,
    uint8_t *ciphertext_and_tag_out);

// Verifies tag, writes plaintext to out (caller-owned, >= ciphertext_len - 16).
// Returns 0 on success, -1 on tag mismatch (constant-time verify via EVP).
int tp_chacha20poly1305_decrypt(
    const uint8_t key[64], const uint8_t nonce[12],
    const uint8_t *aad, size_t aad_len,
    const uint8_t *ciphertext_and_tag, size_t ciphertext_and_tag_len,
    uint8_t *plaintext_out, size_t *plaintext_len_out);

// aes256-gcm: 32-byte key, 12-byte IV (SSH construction: iv || seq with
// carry, built Dart-side), 16-byte tag appended on seal / expected on open.
int tp_aes256gcm_seal(
    const uint8_t key[32], const uint8_t iv[12],
    const uint8_t *aad, size_t aad_len,
    const uint8_t *plaintext, size_t plaintext_len,
    uint8_t *ciphertext_and_tag_out);

int tp_aes256gcm_open(
    const uint8_t key[32], const uint8_t iv[12],
    const uint8_t *aad, size_t aad_len,
    const uint8_t *ciphertext_and_tag, size_t ciphertext_and_tag_len,
    uint8_t *plaintext_out, size_t *plaintext_len_out);
```

- Also produces: `build.sh` with usage `./build.sh [output-dir]` defaulting to `native/`, compiling `cc -O2 -shared -fPIC tp_sshd_crypto.c -o <dir>/libtp_sshd_crypto.so -lcrypto` (plus a macOS arm64/x64 note: same command works; `-arch universal` only for CI).

- [ ] **Step 1: Write `tp_sshd_crypto.h`** with the four declarations above plus a comment header explaining the shim is translation-only (crypto comes from libcrypto).

- [ ] **Step 2: Write `tp_sshd_crypto.c`.** Implementation notes (EVP, OpenSSL 3.x compatible):
  - chacha: the OpenSSH construction needs TWO cipher streams. Length encryption: `EVP_EncryptInit(EVP_chacha20())` with K_2 and nonce, encrypt 4 bytes. Payload + tag: use `EVP_CIPHER_CTX` with `EVP_chacha20_poly1305()` — but note the OpenSSH variant differs from the RFC 8439 AEAD construction (OpenSSH computes the Poly1305 key as chacha20(K_1, nonce) first 32 bytes, then tags `encrypted_length || encrypted_body` with AAD = the encrypted length). **Therefore the shim cannot use `EVP_chacha20_poly1305` directly**; it must: (a) derive the poly1305 key by encrypting 32 zero bytes with `EVP_chacha20()` under K_1+nonce; (b) encrypt the body with `EVP_chacha20()` under K_1+nonce; (c) compute the tag with `EVP_MAC`/`EVP_Poly1305` (OpenSSL 3) or a manual poly1305 (see note) over `aad || encrypted_length || ciphertext` with the RFC 8439 padding rules. If `EVP_Poly1305` is unavailable in the target libcrypto (macOS LibreSSL), implement poly1305 in C (~60 lines, the reference implementation is public domain) — decide at implementation time and document the choice in the file header.
  - aes-gcm: `EVP_chacha20` sibling — `EVP_EncryptInit_ex(EVP_aes_256_gcm())`, `EVP_CIPHER_CTX_ctrl(EVP_CTRL_GCM_SET_IVLEN, 12)`, set AAD via `EVP_EncryptUpdate(ctx, NULL, &len, aad, aad_len)`, then plaintext, then `EVP_CTRL_GCM_GET_TAG`/`EVP_CTRL_GCM_SET_TAG` + `EVP_DecryptFinal_ex` returns the verify result.
  - All functions return `-1` on any EVP failure path; no output written on failure.

- [ ] **Step 3: Write `build.sh`** (per the Produces note; `set -euo pipefail`; prints the output path).

- [ ] **Step 4: Compile and smoke-test in C.** Add a tiny `native/selftest.c` (NOT shipped — gitignored) with a `main()` that runs one RFC 8439 vector through each function and prints OK; compile both, run:

```bash
cd client/packages/dartssh2/native
cc -O2 -shared -fPIC tp_sshd_crypto.c -o libtp_sshd_crypto.so -lcrypto
cc -O2 selftest.c -o selftest -lcrypto -L. -ltp_sshd_crypto -Wl,-rpath,.
./selftest   # expect: all vectors OK
```

- [ ] **Step 5: `.gitignore`** — append `native/libtp_sshd_crypto.so`, `native/selftest`, `native/selftest.c`? (selftest.c IS worth committing as the C-level KAT — commit it; ignore only the binaries).

- [ ] **Step 6: Commit (fork).** On branch `differential-fixes`:

```bash
git add native/ .gitignore
git commit -m "feat(crypto): C shim over libcrypto for chacha20-poly1305 (OpenSSH variant) and aes256-gcm"
```

Then the parent repo: `git add client/packages/dartssh2 && git commit -m "chore: bump dartssh2 fork for the crypto shim"`.

---

### Task 2: FFI loader + known-answer tests (TDD)

**Files:**
- Create: `client/packages/dartssh2/lib/src/utils/native_crypto.dart`
- Create: `client/packages/dartssh2/test/src/native_crypto_kat_test.dart`

**Interfaces:**
- Consumes: Task 1's C ABI and `build.sh` output (`native/libtp_sshd_crypto.so`).
- Produces (the Dart API Tasks 3–4 call — exact):

```dart
/// Hard loader + bindings for the tp_sshd_crypto shim. Opening the library
/// is a late final: the first call throws a descriptive error naming the
/// expected path and the native/build.sh remedy.
class NativeCrypto {
  /// Throws [StateError] naming the searched path and remedy if the library
  /// cannot be opened (hard dependency — no fallback).
  static final DynamicLibrary _lib = _open();

  /// OpenSSH EtM chacha20-poly1305. [key] 64 bytes (K_1||K_2), [nonce] 12
  /// bytes (4 zero + BE sequence), tag appended to the returned buffer.
  /// Returned buffer length = plaintext.length + 16.
  static Uint8List chachaEncrypt(Uint8List key, Uint8List nonce,
      Uint8List aad, Uint8List plaintext);

  /// Throws [ArgumentError] on tag mismatch (the transport maps this to the
  /// same teardown a pointycastle auth failure produces today).
  static Uint8List chachaDecrypt(Uint8List key, Uint8List nonce,
      Uint8List aad, Uint8List ciphertextAndTag);

  /// AES-256-GCM. [key] 32, [iv] 12; tag appended on seal, expected on open.
  static Uint8List aesGcmSeal(Uint8List key, Uint8List iv,
      Uint8List aad, Uint8List plaintext);

  static Uint8List aesGcmOpen(Uint8List key, Uint8List iv,
      Uint8List aad, Uint8List ciphertextAndTag);
}
```

- Loader resolution order (hard, no probing beyond this): `build.sh` output at `native/libtp_sshd_crypto.so` relative to the package root (resolved via `Platform.script`/`Platform.resolvedExecutable` — handle both `dart test` (kernel) and `dart run` layouts; the practical pattern: try `lib/src/utils/../../../native/` computed from a `Directory.current` + package-root walk, and document that the test harness always runs from the package dir). If not found, throw.

- [ ] **Step 1: Write the failing KAT test** — `native_crypto_kat_test.dart` with, at minimum:
  - RFC 8439 §2.8.2 AEAD test vector through `chachaEncrypt`/`chachaDecrypt` (the standard construction — the shim's poly1305 path is exactly RFC 8439 once the OpenSSH key-derivation is done Dart-side; ALSO add one OpenSSH-construction vector: the PROTOCOL.chacha20poly1305 example or a self-generated vector pinned from the CURRENT pure-Dart implementation's output — run `OpenSSHChaCha20Poly1305.encryptPacket` once on a fixed key/seq/packet, paste the bytes into the test as the expected value; that pins the OpenSSH construction exactly).
  - NIST GCM test case 15 or 16 (aes-256) through `aesGcmSeal`/`aesGcmOpen` (note: pass a 12-byte IV; the NIST vector supplies one).
  - Tamper test: flip one bit in the tag → `aesGcmOpen` throws.
  - Empty-AAD and empty-plaintext edge cases for both families.

```dart
// Vector shape (fill the exact bytes from the RFC/NIST documents at
// implementation time — the sources are cited in the test comments):
test('RFC 8439 2.8.2 AEAD round trip', () {
  final key = Uint8List.fromList(rfc8439Key);
  final nonce = Uint8List.fromList(rfc8439Nonce);
  final aad = Uint8List.fromList(rfc8439Aad);
  final plaintext = Uint8List.fromList(rfc8439Plaintext);
  final sealed = NativeCrypto.chachaEncrypt(key, nonce, aad, plaintext);
  expect(sealed.length, plaintext.length + 16);
  expect(sealed.sublist(plaintext.length), rfc8439ExpectedTag);
  final opened = NativeCrypto.chachaDecrypt(key, nonce, aad, sealed);
  expect(opened, plaintext);
});
```

- [ ] **Step 2: Run to verify it fails** — `cd client/packages/dartssh2 && ./native/build.sh && dart test test/src/native_crypto_kat_test.dart` → FAIL (native_crypto.dart does not exist).

- [ ] **Step 3: Implement `native_crypto.dart`** per the Produces signature: `DynamicLibrary.open` at the resolved path (throw `StateError` with path + `native/build.sh` remedy on failure), `lookupFunction` for the four symbols, `malloc`/`free`-managed pointer copies (use `package:ffi` if the fork already has it — check pubspec; otherwise raw `malloc` from `dart:ffi`), and the buffer arithmetic (`plaintext_len_out` via `Pointer<Size>`).

- [ ] **Step 4: Run the KAT test to green.** Also verify the error path: temporarily rename the .so, run a `test(() => expect(() => NativeCrypto.chachaEncrypt(...), throwsStateError))` case, rename back (or resolve the library lazily and reload — simplest: one test with the file temporarily moved, done manually and recorded in the report).

- [ ] **Step 5: Full fork gate** — `dart analyze` (0 errors) && `dart test` (712+ green; the KAT file adds its tests; the ciphers are not yet swapped so everything else is unchanged).

- [ ] **Step 6: Commit (fork + parent gitlink bump).**

```bash
# fork (differential-fixes)
git add lib/src/utils/native_crypto.dart test/src/native_crypto_kat_test.dart
git commit -m "feat(crypto): FFI loader + known-answer tests for the libcrypto shim"
# parent
git add client/packages/dartssh2
git commit -m "chore: bump dartssh2 fork — FFI loader"
```

---

### Task 3: Swap the ChaCha20-Poly1305 implementation

**Files:**
- Modify: `client/packages/dartssh2/lib/src/utils/openssh_chacha20_poly1305.dart`
- Modify: `client/packages/dartssh2/test/src/native_crypto_kat_test.dart` (add the pure-Dart-vs-FFI equivalence case if not already pinned there)

**Interfaces:**
- Consumes: `NativeCrypto.chachaEncrypt/chachaDecrypt` (Task 2).
- Produces: `OpenSSHChaCha20Poly1305` with the FROZEN class interface (`keySize`, `encryptPacket(Uint8List packet, int sequenceNumber)`, `decryptPacket(...)`, constructor taking the 64-byte key material) — internals now delegate to `NativeCrypto`.

- [ ] **Step 1: Pin the current implementation's outputs first.** Before touching the class, run a quick script (or test) that encrypts three representative packets (empty-ish 4+1+0+pad, mid-size ~1 KiB, large ~32 KiB) with fixed key/sequence and prints the ciphertext hex. Paste into `native_crypto_kat_test.dart` as `openSSHConstructionPinnedVectors`. This is the equivalence oracle: the refactored class must produce identical bytes.

- [ ] **Step 2: Rewrite the class internals.** Keep the class shape and doc comments; replace `_cryptLength`/`_payloadCipher`/`_poly1305Key`/`_authenticationTag` choreography with: build the 12-byte nonce (`_nonce(sequenceNumber)` stays — it builds the OpenSSH construction), split nothing (pass the whole 64-byte key), call `NativeCrypto.chachaEncrypt(key, nonce, aad: encryptedLength, plaintext: packet[4..])` — mapping the OpenSSH AAD semantics exactly as the current code does (verify against the current `encryptPacket` body: AAD is the ENCRYPTED length, the length itself is encrypted with K_2 under the same nonce). `decryptPacket` mirrors it: `chachaDecrypt` with AAD = the received encrypted length; on `ArgumentError` rethrow as the same error type the transport saw from pointycastle auth failures (check what `decryptPacket` throws today and preserve it).

- [ ] **Step 3: Run the pinned-vector test** — must be byte-identical. Then the full fork gate (`dart analyze` && `dart test`) — every handshake/exec/SFTP/rekey test now exercises the FFI chacha; all must stay green.

- [ ] **Step 4: Run tp_sshd's suite** — `cd client/packages/tp_sshd && dart test` (104+ green through the FFI path).

- [ ] **Step 5: Commit (fork + parent gitlink bump)** — `feat(crypto): chacha20-poly1305 packets via the libcrypto shim`.

---

### Task 4: Swap the AES-256-GCM implementation

**Files:**
- Modify: `client/packages/dartssh2/lib/src/ssh_transport.dart` (`_processAead` only — its signature and every call site stay)

**Interfaces:**
- Consumes: `NativeCrypto.aesGcmSeal/aesGcmOpen` (Task 2).
- Produces: `_processAead` with the frozen signature, internals delegating to NativeCrypto.

- [ ] **Step 1: Pin current outputs** — same procedure as Task 3 Step 1 but for `_processAead`: three fixed (key, iv, sequence, aad, input) cases, hex-pinned. `_processAead` is private; pin via a small test that constructs `SSHTransport` far enough to call it is disproportionate — instead pin through the existing AEAD cipher algorithm test if one exists (`grep -rn "aes256gcm" test/`), or extract the equivalence by running the KAT vectors through both the pointycastle expression and `NativeCrypto.aesGcmSeal` in the KAT file (the NIST vectors already do this for the new path; add the pointycastle mirror for the same vectors and assert equality).

- [ ] **Step 2: Rewrite `_processAead` internals** — build nonce via the existing `_nonceForSequence(iv, sequence)` (keep the function), then `forEncryption ? NativeCrypto.aesGcmSeal(key, nonce, aad, input) : NativeCrypto.aesGcmOpen(...)`. Map auth failure to the same exception type pointycastle's GCM throws on failure (check `cipher.process` failure mode — likely `ArgumentError` from the pointycastle GCM; the KAT tamper test pins the new failure shape). Remove the now-unused pointycastle GCM import if nothing else uses it.

- [ ] **Step 3: Gate** — fork `dart analyze` + `dart test` (the fork's AEAD tests + the ssh_client tests over test.rebex.net may exercise aes256gcm when negotiated — those are network-gated, skip-by-default per the earlier rebex gating); tp_sshd `dart test` (tp_sshd advertises aes256-gcm; a client negotiating it in a dual test exercises this path — if no existing test negotiates aes256gcm, add one `server_handshake_test` case forcing `SSHCipherType.aes256gcm` in the client config, asserting login + exec round trip).

- [ ] **Step 4: Commit (fork + parent gitlink bump)** — `feat(crypto): aes256-gcm packets via the libcrypto shim`.

---

### Task 5: Remove the pure-Dart cipher code + benchmark + docs

**Files:**
- Modify: `client/packages/dartssh2/lib/src/utils/openssh_chacha20_poly1305.dart` (delete dead pure-Dart helpers after the swap — poly1305/chacha pointycastle usage)
- Modify: `client/packages/tp_sshd/example/bench_cipher.dart` (bench the FFI path; keep a reference table of the old pure-Dart numbers as a comment)
- Modify: `docs/DEVELOPMENT.md` (native build requirement note)

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces: the acceptance evidence — bench numbers and end-to-end numbers recorded in the task report and DEVELOPMENT.md.

- [ ] **Step 1: Delete dead code.** After both swaps, `OpenSSHChaCha20Poly1305`'s pointycastle imports and helper methods are dead — remove them (hard dependency: no fallback path remains). `dart analyze` confirms no dangling references.

- [ ] **Step 2: Extend `bench_cipher.dart`** — it currently benches `OpenSSHChaCha20Poly1305.encryptPacket` directly (which now IS the FFI path). Update its header comment to say so, keep 4 KiB + 32 KiB runs, and add the historical pure-Dart baseline (40–58 MB/s, measured 2026-09-10) as a comment for context. Run it and record the number (this is acceptance criterion 2 evidence — ≥500 MB/s expected on 32 KiB).

- [ ] **Step 3: End-to-end measurement** — start the demo server (`dart run example/demo_sshd.dart --port 2222`) and time a 50 MB SFTP get with the real OpenSSH client (the exact procedure from the original differential session):

```bash
dd if=/dev/urandom of=$HOME/.tp_sshd_demo/sftp-root/big.bin bs=1M count=50
# sftp get big.bin, time it; MB/s = 50 / seconds
```

Record the number (acceptance criterion 3 — ≥80 MB/s, or the residual-bottleneck finding for Phase 2). Also rerun `dart run tool/differential/run_audit.dart --area all` — must regenerate clean (acceptance criterion 4).

- [ ] **Step 4: DEVELOPMENT.md note** — under the tp_sshd/dartssh2 toolchain section: `dart test` for the fork requires `native/build.sh` first (one command); shipped prebuilts live in `native/prebuilt/` (CI-generated, commit policy same as flutter_pty_new).

- [ ] **Step 5: Full gates + commit.** Fork: `dart analyze` + `dart test`. tp_sshd: `dart analyze` + `dart test`. Commit fork (`chore(crypto): drop the pure-Dart cipher implementations`) + parent gitlink bump + the bench/docs commits in the parent.

---

### Task 6: CI prebuild matrix (build-only)

**Files:**
- Create: `client/packages/dartssh2/native/ci-build-all.sh` (matrix driver)
- Create: `client/packages/dartssh2/native/prebuilt/` (committed artifacts, one dir per platform)
- Modify: CI workflow files if the repo's lanes are in-repo (check `.github/workflows/` or equivalent; if CI config lives elsewhere, the script is the deliverable and CI wiring is a follow-up documented in the report)

**Interfaces:**
- Consumes: Task 1's shim + build.sh.
- Produces: prebuilt libraries for linux/{x64,arm64}, macos/universal, windows/x64 (vcpkg OpenSSL), android/{arm64-v8a,x86_64} (NDK), each validated by a load+KAT smoke where the host can run it (linux x64 natively; others by artifact presence + the C selftest cross-compiled where feasible).

- [ ] **Step 1: Write `ci-build-all.sh`** — per-platform matrix: linux native `cc`; macos `cc -arch arm64 -arch x86_64`; windows via `x86_64-w64-mingw32-gcc` + vcpkg openssl (document the exact vcpkg triplet in the script header); android via NDK `clang --target=aarch64-linux-android2X`. Each lane: build, run `native/selftest` when the host can execute it, else `file`/size sanity, copy into `prebuilt/<platform>/`.

- [ ] **Step 2: Produce and commit the Linux x64 prebuilt** from this machine (the only host here): `native/build.sh native/prebuilt/linux/x64/` — commit it (binary in git, same policy as flutter_pty_new's prebuilts). The other lanes' artifacts are CI outputs when the matrix runs; if no CI wiring is reachable from this worktree, commit the script + directory structure and record in the report that artifact production for the other lanes is a CI follow-up (Phase 1's runtime gate is Linux per the spec).

- [ ] **Step 3: Loader note** — `native_crypto.dart`'s doc comment already names `prebuilt/` as the shipped layout; update its resolution note to document that the app packaging flow (flutter build) picks up `prebuilt/` per flutter_pty_new's jniLibs/bundling pattern, while `dart test`/`dart run` use the `build.sh` output.

- [ ] **Step 4: Final full gates + commit** (fork: script + prebuilt linux; parent: gitlink bump + any doc line). Record in the report: which lanes produced artifacts here vs. which need CI.

---

## Self-Review

**Spec coverage:** shim + build.sh (T1), loader + KAT (T2), chacha swap with frozen shape (T3 = spec integration point 1), aes-gcm swap (T4 = point 2), loader hard-dependency error (T2 Produces + Step 4), dead-code removal/hard dependency (T5 = spec decision), bench ≥500 + end-to-end ≥80 + differential regen (T5 Steps 2–4 = acceptance criteria 2–4), suites-green (T3/T4/T5 gates = criterion 1), CI prebuilds + Linux gate + other-platform smoke (T6 = spec Testing/Non-goals), DEVELOPMENT.md (T5 Step 4). Phase 2 explicitly out (spec Non-goals).

**Placeholder scan:** the KAT vectors are named by their RFC/NIST section numbers with the procedure to transcribe them stated (they are published constants, not code the plan can invent); the OpenSSH-construction vectors are pinned from the live implementation (procedures given). The one implementation-time decision (EVP_Poly1305 vs. manual poly1305 for macOS) is a documented decision point with both paths specified — not a placeholder.

**Type consistency:** `NativeCrypto.chachaEncrypt/chachaDecrypt/aesGcmSeal/aesGcmOpen` defined in T2, consumed verbatim in T3/T4; the frozen shapes (`encryptPacket(packet, sequenceNumber)`, `_processAead({key, iv, sequence, aad, input, forEncryption})`) are quoted in the Global Constraints and preserved by T3/T4 steps; `tp_chacha20poly1305_encrypt/decrypt`, `tp_aes256gcm_seal/open` C names defined in T1, bound in T2.
