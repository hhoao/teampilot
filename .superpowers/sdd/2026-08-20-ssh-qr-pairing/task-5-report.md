# Task 5 Report

## Status

COMPLETE. Task 5 now provides an sshd-gated LAN `ConnectAgent`, a production
local SSH host-key handshake scanner, stable host ID persistence, an injectable
pairing HTTP binding, and a cross-platform short-lived self-signed certificate
provider backed by bundled Dart crypto. No `openssl` executable is used.

The binding security amendment is enforced:

- stopped sshd prevents binding and offer minting;
- an empty `SHA256:` handshake fingerprint capture prevents binding and offer
  minting;
- the HTTPS server binds only to the explicitly advertised interface address;
- stop/regenerate invalidate prior invite tokens;
- the offer pin is the SHA-256 digest of the generated leaf DER certificate;
- certificate and key files are mode `0600` on POSIX systems.

## Changed Files

- `client/lib/services/connect/connect_agent.dart`
  - Added `ConnectAgent`, `PairingBinding`, `PairingHttpRequest`, injected bind
    seam, LAN/extra/registered-relay offer construction, lifecycle, and pairing
    POST dispatch.
- `client/lib/services/connect/connect_settings_store.dart`
  - Added JSON-backed stable 16-character host ID persistence at
    `<appDataRoot>/connect/settings.json` via injected `Filesystem`.
- `client/lib/services/connect/pairing_certificate.dart`
  - Added `PairingCertificateProvider`, canned-provider seam, and production
    `ConnectTls` RSA-2048/X.509 generation using bundled `pointycastle`.
- `client/lib/services/connect/sshd_presence.dart`
  - Added the 300 ms loopback TCP presence probe, platform enable hints, and
    unauthenticated `dartssh2` key-exchange fingerprint capture.
- `client/test/services/connect/connect_agent_test.dart`
  - Added eight agent/settings/certificate tests with fake pairing binding and
    in-memory authorized keys/filesystem.
- `client/pubspec.yaml`
  - Promoted `pointycastle` and `posix` to direct dependencies.
- `client/pubspec.lock`
  - Recorded both dependencies as direct.

## Tests / Outputs

- RED:
  - `cd client && flutter test test/services/connect/connect_agent_test.dart`
  - Expected compilation failure: Task 5 service types/files did not exist.
- GREEN:
  - `cd client && flutter test test/services/connect/connect_agent_test.dart`
  - Result: `00:00 +8: All tests passed!`
- Formatting:
  - `cd client && dart format --output=none --set-exit-if-changed lib/services/connect/connect_agent.dart lib/services/connect/connect_settings_store.dart lib/services/connect/pairing_certificate.dart lib/services/connect/sshd_presence.dart test/services/connect/connect_agent_test.dart`
  - Result: `Formatted 5 files (0 changed)`.
- Focused analysis:
  - `cd client && dart analyze lib/services/connect/connect_agent.dart lib/services/connect/connect_settings_store.dart lib/services/connect/pairing_certificate.dart lib/services/connect/sshd_presence.dart test/services/connect/connect_agent_test.dart`
  - Result: `No issues found!`
- Focused regression suite:
  - `cd client && flutter test test/services/connect`
  - Result: `00:00 +19: All tests passed!`
- `git diff --check` and `git diff --cached --check`
  - Result: no whitespace errors.

## Commits

- `4bd689ef0` — `feat(connect): add sshd-gated LAN pairing agent`
- Report-only follow-up commit records this file.

## Concerns

- Verification was intentionally scoped to `client/test/services/connect`; the
  repository-wide analyze/test commands remain for the integrating agent.
- The production scanner records the host identity selected by the local SSH
  handshake. It does not enumerate every host-key algorithm exposed by sshd.
- Fresh certificate/key files remain under the application data certificate
  directory after expiry; later lifecycle maintenance may prune expired files.

## Review Fix Report

### Status

COMPLETE. Both Task 5 review findings are fixed:

- `startQrSession`, `stopQrSession`, and `regenerateQr` now share one lifecycle
  lock. A stop queued behind an in-flight start closes the newly created
  listener before it returns, so the start cannot orphan a binding.
- Pairing POST bodies are bounded by bytes while the stream is consumed. A
  declared `Content-Length` above 64 KiB is rejected before subscription, and
  chunked bodies stop as soon as their cumulative bytes cross the limit. The
  HTTPS adapter returns HTTP 413 without calling `join()` on the body.

### Changed Files

- `client/lib/services/connect/connect_agent.dart`
- `client/test/services/connect/connect_agent_test.dart`

### TDD / Verification

- Lifecycle RED:
  - `flutter test test/services/connect/connect_agent_test.dart --plain-name "stop waits for and closes an in-flight start binding"`
  - Result before fix: failed because `binding.closed` was `false`.
- Lifecycle GREEN:
  - Same command after the shared lifecycle lock.
  - Result: `+1: All tests passed!`
- Request-limit RED:
  - `flutter test test/services/connect/connect_agent_test.dart --plain-name "rejects an oversized content length before listening"`
  - Result before fix: compilation failed because the bounded reader and
    oversize exception did not exist.
- Focused Task 5 GREEN:
  - `flutter test test/services/connect/connect_agent_test.dart`
  - Result: `+11: All tests passed!`
- Formatting and analysis:
  - `dart format --output=none --set-exit-if-changed lib/services/connect/connect_agent.dart test/services/connect/connect_agent_test.dart`
  - Result: `Formatted 2 files (0 changed)`.
  - `dart analyze lib/services/connect/connect_agent.dart test/services/connect/connect_agent_test.dart`
  - Result: `No issues found!`
- Connect regression suite:
  - `flutter test test/services/connect`
  - Result: `+22: All tests passed!`

### Commit

- `1c68d719a` — `fix(connect): serialize pairing lifecycle and bound requests`

### Concerns

- Repository-wide analysis and tests remain for the integrating agent; focused
  Task 5 and connect-service verification is clean.
