# dartssh2 FFI Crypto Acceleration — Phase 1 Design

Date: 2026-09-15
Status: Approved (design phase)

## Problem

tp_sshd's end-to-end SFTP throughput is ~36 MB/s versus ~170 MB/s for the
system OpenSSH sshd on the same machine (differential audit, row C10). The
measured ceiling is the pure-Dart cryptography: `bench_cipher.dart` shows
the vendored pointycastle/pinenacl ChaCha20-Poly1305 at 40–58 MB/s on
32 KiB packets, and every SSH packet pays that cost in both directions.
Phase 1 removes the crypto ceiling. Packet-path copy reduction and larger
packet-size negotiation are deliberately deferred to a separate Phase 2.

## Decision

Replace the two cipher implementations inside the dartssh2 fork with FFI
calls into a small C shim backed by the platform's libcrypto (OpenSSL on
Linux, BoringSSL-derived on Android, LibreSSL/CommonCrypto-adjacent
system libcrypto on macOS, vendored OpenSSL on Windows). The shim is
built by CI for all supported platforms and shipped in-repo next to the
fork, following the distribution model flutter_pty_new already uses.

Scope decisions (user-ratified):

- **FFI + full-chain goal, phased delivery**: Phase 1 is FFI crypto only.
  Phase 2 (copy reduction, larger packet negotiation) is a future plan,
  informed by what Phase 1's end-to-end numbers show.
- **Self-built C shim + CI prebuilds** (not system dlopen, not a pub
  package): minimal interface, no system-API version drift, identical
  shape to the repo's existing native dependency.
- **Hard dependency**: no pure-Dart fallback in shipped builds. Loading
  failure is an immediate error.
- **Test environment**: `dart test` runs on a locally compiled shim
  (`native/build.sh`, one `cc -shared` invocation) — CI and dev machines
  build it before running tests. No prebuilt needed for the test path.

## Architecture

```
client/packages/dartssh2/
  native/
    tp_sshd_crypto.c/.h      # ~200-line shim: OpenSSH-variant
                             # chacha20-poly1305 + aes256-gcm over libcrypto
    build.sh                 # local/test build (cc -shared, ~1s)
    prebuilt/                # CI artifacts, committed for distribution
      linux/x64+arm64/libtp_sshd_crypto.so
      macos/universal/libtp_sshd_crypto.dylib
      windows/x64/tp_sshd_crypto.dll
      android/{arm64-v8a,x86_64}/libtp_sshd_crypto.so
  lib/src/utils/native_crypto.dart
                             # FFI bindings + hard loader
                             # (DynamicLibrary.open, throws on failure)
```

The shim exposes two function families and nothing else:

```c
// OpenSSH EtM variant: encrypts the 4-byte length with K_1 and the
// payload with K_2, producing a 16-byte Poly1305 tag (RFC 8439 + PROTOCOL.chacha20poly1305).
int tp_chacha20poly1305_encrypt(
    const uint8_t key[64], uint64_t nonce_be[12-byte seq as 4 BE zero-padded],
    const uint8_t *plaintext, size_t len,
    uint8_t *ciphertext_and_tag_out);

int tp_chacha20poly1305_decrypt(...);  // symmetric; returns -1 on tag mismatch

// aes256-gcm: 12-byte IV (SSH nonce construction), 16-byte tag.
int tp_aes256gcm_seal(const uint8_t key[32], const uint8_t iv[12], ...);
int tp_aes256gcm_open(...);            // returns -1 on auth failure
```

Exact signatures are finalized at implementation time to match what the
transport hands the cipher today (whole-packet buffers, tag appended);
the shim never allocates — caller-owned buffers in and out.

## Integration points (all inside the dartssh2 fork)

1. **ChaCha20-Poly1305 path** — `OpenSSHChaCha20Poly1305`
   (`lib/src/utils/openssh_chacha20_poly1305.dart`):
   `encryptPacket`/`decryptPacket` delegate to the shim via
   `native_crypto.dart`. Class name and signatures unchanged; the
   transport layer is unaware.
2. **AES-256-GCM path** — the cipher construction site around
   `ssh_transport.dart:1278` (where `SSHCipherType.aes256gcm` maps to a
   pointycastle instance today) gains a shim-backed class implementing
   the same `BlockCipher`-shaped interface the transport expects.
3. **Loader** — `native_crypto.dart` resolves the library: `DynamicLibrary.open`
   on the prebuilt path appropriate to `Platform` (the flutter_pty_new
   pattern). Failure throws a descriptive error naming the expected path
   and the `native/build.sh` remedy. This is the hard dependency.

Both tp_sshd (server) and the app's SSH client share this transport, so
one change accelerates both directions of every connection.

## Error handling

| Scenario | Behavior |
|---|---|
| Prebuilt library missing at runtime | Immediate load error naming the path and remedy (hard dependency, by design) |
| Tag mismatch / auth failure | Same semantics as today: decrypt failure surfaces as a transport error and tears down the connection — the shim returns -1, the Dart wrapper throws the existing error type |
| libcrypto lacks EVP cipher (very old) | Build-time problem, not runtime: CI matrix fails there; no runtime probing |

## Testing

- **Equivalence**: the existing suites ARE the correctness gate — tp_sshd
  104 tests + dartssh2 fork 712 tests, every handshake/exec/SFTP/rekey
  round trip exercising the FFI ciphers. All must stay green.
- **KAT vectors**: a small dart test runs known-answer tests (RFC 8439
  vectors, an OpenSSH chacha packet vector, an aes256-gcm NIST vector)
  through the shim — catches endianness/nonce-construction regressions
  that protocol round trips might mask when both sides share a bug.
- **Benchmark gate**: `example/bench_cipher.dart` (in tp_sshd) extended
  to bench both implementations. Acceptance: FFI chacha ≥ 500 MB/s on
  32 KiB packets (conservative floor; libcrypto SIMD typically reaches
  GB/s). Recorded before/after in the plan ledger.
- **Test environment**: CI and dev machines run `native/build.sh` before
  `dart test` — the loader in test mode opens the locally built library.
  The Linux CI lane is the Phase 1 gate; other platforms' prebuilds land
  via CI but are validated by build-only smoke (load + KAT), not a full
  device matrix.

## Acceptance criteria

1. `dart test` green in tp_sshd (104+) and the fork (712+) with the FFI
   ciphers active, after `native/build.sh`.
2. `bench_cipher` FFI path ≥ 500 MB/s (32 KiB packets, same machine as
   the 40–58 MB/s baseline).
3. End-to-end: SFTP bulk transfer ≥ 80 MB/s via the tp_sshd demo harness
   (vs 36 MB/s today). If the end-to-end number stays below 80 despite a
   fast cipher, the residual bottleneck is the packet path — that
   measurement is the Phase 2 go/no-go evidence, recorded in the ledger.
4. Differential harness `--area all` still regenerates clean (the
   protocol behavior must be unchanged by the crypto swap).

## Non-goals (Phase 2 candidates, not this spec)

- Packet-path copy reduction (`sublistView` zero-copy).
- Larger channel packet-size negotiation for fork-client ↔ tp_sshd pairs.
- FFI for ed25519 signing/verification (handshake-only cost, not
  throughput-relevant).
- Windows/Android runtime validation beyond build + KAT smoke (the app's
  release packaging flows pick those up).

## Maintenance notes

- The shim's C is translation-only; the crypto comes from libcrypto. The
  only platform-specific build input is the libcrypto linkage (system
  everywhere except Windows, vendored there).
- Prebuilts are committed, so a `dart pub get` user never compiles C;
  only test runners and CI do.
- The fork now carries a native build chain — the same operational shape
  as flutter_pty_new, documented in DEVELOPMENT.md as part of this work.
