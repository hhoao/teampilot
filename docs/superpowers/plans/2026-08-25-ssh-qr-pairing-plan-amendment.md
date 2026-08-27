# SSH QR pairing plan amendment

> This document is mandatory when implementing
> `2026-08-20-ssh-qr-pairing.md`.

## Task 5 replacement requirements

- Add a production `SshdHostKeyScanner` that performs a local, unauthenticated
  handshake and returns `SHA256:` host-key identities. `ConnectAgent` does not
  mint an offer if the scanner returns no fingerprints.
- Replace the process-based TLS generation with an injected cross-platform
  `PairingCertificateProvider`. Tests use a canned certificate; production
  persists a newly generated short-lived certificate/key with owner-only mode.

## Task 10 protocol requirements

- `/dial` accepts `deviceId` and exactly one opaque credential
  (`inviteToken` or `relayGrant`). It forwards both values unchanged only to the
  registered desktop in its dial notification.
- The relay logs neither credential and grants no authorization merely by
  accepting `/dial`.

## Task 11 replacement requirements

- `ConnectRelayClient` validates a pair invite or SSH grant before it opens a
  splice. Grant hashes are compared in constant time and are scoped to
  `deviceId` plus `hostId`.
- Rejection closes the dial/splice without touching local pairing HTTP or sshd.
- Relay registration is owned by the application-lifetime ConnectAgent; QR
  visibility controls only pairing listener/token lifetime.

## Required tests

- A relay SSH dial with missing, invalid, revoked, or wrong-device grant never
  reaches the desktop loopback sshd.
- A relay pair dial with an expired/currently-invalid invite never reaches the
  pairing handler.
- An empty local host-key scan prevents offer minting.
- Certificate provider tests prove no process runner is required in production
  wiring and the emitted leaf hash is the advertised TLS pin.
