# SSH QR pairing security amendment

This amendment is approved with the SSH QR pairing design dated 2026-08-20.
It overrides conflicting relay and TLS implementation details.

## Relay authorization

The relay remains a byte pipe, but its `dial` notification to the registered
desktop includes the opaque `inviteToken` or `relayGrant` supplied by the
phone. Before opening a `splice`, `ConnectAgent` validates the credential:

- a pairing channel accepts only the current, unused QR invite while the QR
  session is active;
- an SSH channel accepts only a non-revoked, constant-time-matched hash of a
  grant issued for the requested `deviceId` and desktop `hostId`.

The relay must not decide authorization and must not log the opaque credential.
The agent sends a rejection and does not open a splice when validation fails.

## SSH host-key fingerprints

The desktop obtains fingerprints through a local unauthenticated SSH handshake
to the detected sshd listener. It never reads private host-key files. The
captured `SHA256:` identities are placed in the offer; an empty capture prevents
offer minting. The phone accepts only one of these identities and never invokes
the normal trust prompt for a paired profile.

## Pairing TLS certificate

The production certificate provider must work on Windows, macOS, and Linux.
It creates a fresh, short-lived self-signed leaf certificate and private key in
the application data directory with owner-only permissions. It may use a
bundled, versioned crypto implementation; it must not require a user-installed
`openssl` executable. The offer pins the SHA-256 hash of the generated leaf DER
certificate, and the phone compares that hash during the pairing request.

## Lifecycle

When Connect is enabled, the desktop agent maintains relay registration even
when the QR UI is closed. The HTTPS pairing listener and invite token exist only
while the QR UI is visible. Relay pairing is therefore unavailable after the QR
session closes, while a valid non-revoked grant can still open an SSH splice.
