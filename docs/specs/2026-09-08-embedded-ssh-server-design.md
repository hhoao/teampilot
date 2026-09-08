# Embedded SSH Server Design

Date: 2026-09-08
Status: Approved (design phase)

## Problem

QR pairing requires the desktop to run a system sshd: `ConnectAgent` probes
`127.0.0.1:22` and refuses to mint an offer when nothing listens
(`connect_agent.dart:206-214`). This dependency is broken three ways on
Windows:

1. OpenSSH Server is not installed by default, and Microsoft has deprecated
   OpenSSH for Windows (removal planned from future releases).
2. `AuthorizedKeysFile` writes `%USERPROFILE%\.ssh\authorized_keys`
   (`app_shell.dart:1608-1612`), but Windows sshd reads
   `C:\ProgramData\ssh\administrators_authorized_keys` for admin-group users
   — pairing "succeeds" and authentication always fails.
3. `SshdPresence` hardcodes port 22; third-party sshd setups are invisible.

Independent of Windows, the phone side already assumes a POSIX remote
(`/bin/bash`, `cd && export && exec` strings — `host_interactive_shell.dart:31`,
`remote_flashskyai_command_builder.dart`), so phone → Windows-desktop is
broken even with OpenSSH installed.

## Decision

Replace the system sshd entirely with an embedded, pure-Dart SSH server that
ships inside the desktop app:

- **Full replacement, not fallback.** Paired phones always connect to the
  embedded server on every desktop platform. No `SshdPresence`, no
  `authorized_keys`.
- **Structured command protocol.** `exec` payloads are JSON
  (`tp1:`-prefixed) carrying `{argv, cwd, env}`, spawned directly — no shell
  strings, no quoting, identical semantics on all platforms.
- **Persisted high port.** Random high port chosen once, persisted in
  `ConnectSettingsStore`, rebound on every launch.
- **Re-pair, not migrate.** Profiles pointing at the old sshd endpoint are
  expected to re-scan the QR.

## Goals

- QR pairing works on stock Windows (and macOS/Linux) with zero OS
  configuration — no optional features, no Remote Login, no firewall port 22.
- Phone → desktop terminal/exec/SFTP/reverse tunnels work identically on
  Windows, macOS, and Linux.
- Authentication is the paired-device registry only; revocation is immediate.
- The SSH server implementation is a standalone, Flutter-free, testable
  package dual-tested against our vendored `dartssh2` client.

## Non-goals

- No password or keyboard-interactive auth (publickey only, fail closed).
- No sandboxing of paired phones — a paired device has the same user-level
  file/process access as the system sshd grants today (it is your desktop).
- No support for third-party SSH clients connecting to the embedded server
  (standard `exec` shell strings are rejected; only `tp1:` structured
  payloads and standard `shell`/`sftp`/forwarding are served).
- No migration path for pre-upgrade paired profiles beyond a guided re-pair
  hint.

## Architecture

```
client/packages/dartssh2 (fork, hhoao/dartssh2)
  └─ lib/protocol.dart            [new] additive public export: SSHMessageReader/
                                    Writer, message/msg_*.dart, kex implementations,
                                    algorithm registries. Zero behavior change.

client/packages/tp_sshd (new package, pure Dart, no Flutter)
  ├─ ssh_server.dart              SSHServer.bind() entry point
  ├─ server/transport.dart        server-role state machine (version exchange,
  │                               KEX responder, host key signing, rekey)
  ├─ server/auth.dart             userauth-publickey with callback verifier
  ├─ server/connection.dart       global requests + channel multiplexing
  │                               (window semantics)
  ├─ server/session.dart          session channel: pty-req / exec / shell / env /
  │                               window-change / signal
  ├─ server/sftp.dart             SFTPv3 server subsystem over an injected FS
  ├─ server/forward.dart          tcpip-forward global request +
  │                               forwarded-tcpip channels
  └─ everything injectable: socket factory, process factory, FS interface

client/lib/services/connect/
  ├─ embedded_ssh_server.dart     [new] owns the tp_sshd instance: host key
  │                               management, port persistence, auth →
  │                               PairedDeviceStore, exec/pty → flutter_pty +
  │                               process factory, SFTP → LocalFilesystem,
  │                               forward → ServerSocket
  └─ connect_agent.dart           [changed] canPair no longer probes 22; offer
                                  endpoints come from the embedded server
```

### Why the fork exports a protocol library

A server needs dartssh2's message codec (`src/message/`), KEX math
(`src/kex/`), and algorithm registries — all currently `lib/src/`
implementation libraries. `SSHTransport` itself cannot be reused: it hardcodes
the client role in the exchange hash (`ssh_transport.dart:1865-1868`). The new
`protocol.dart` export is purely additive (no behavior change, trivially
mergeable with upstream); the server package implements its own transport
state machine on top.

### Lifetime

The embedded server starts with the app (same tier as the relay
registration — app lifetime) and binds a wildcard address (all interfaces)
on the persisted port; access control is the pairing-key auth, so the bind
surface is not the security boundary. The offer's LAN endpoint still names
the single advertise address chosen for the QR session (unchanged). The QR
session remains a separate construct (invite token gating unchanged);
`canPair` now means "embedded server is listening".

### Deleted

`SshdPresence`, `SshdHostKeyScanner`, `AuthorizedKeysFile`, their wiring in
`app_shell.dart:1608-1622`, and `platformSshdEnableHint`.

## Protocol server (tp_sshd)

**Transport.** Server-role state machine reusing fork codecs and KEX math.
Deliberately narrow negotiation surface:

- KEX: `curve25519-sha256`; host key: `ssh-ed25519`
- Ciphers: `chacha20-poly1305@openssh.com`, `aes256-gcm@openssh.com`
- strict KEX (RFC 9142) and rekey; unimplemented services are not advertised
  in KEXINIT

**Auth.** `publickey` only. Verifier callback
`Future<bool> Function(String username, String algorithm, Uint8List blob)`
wired by the app to `PairedDeviceStore`. Username must match the offer's
recorded one. Failed-auth throttling: N failures (6) per connection →
disconnect with increasing delay. Malformed/malicious packets disconnect that
connection only; the listener survives.

**Session channel.** `exec` (structured payload, below), `shell` + `pty-req`
(server picks the OS-native shell: PowerShell on Windows, `$SHELL`/bash on
macOS/Linux), `env`, `window-change`, `signal`. Exit status via the standard
channel request. Keepalive global requests are answered (phone-side
`client.ping()` unchanged).

**SFTP.** SFTPv3 full server implementation (dartssh2's client speaks v3)
against an injected filesystem interface; the app wires `LocalFilesystem`
including the Windows path context.

**Forwarding.** `tcpip-forward` binds loopback only, ports live with the
requesting connection; accepted connections open `forwarded-tcpip` channels
pumped back to the phone. TeamBus/MCP/agent-status reverse-tunnel semantics
are identical to today.

## Structured command protocol

All phone-side remote command emission points (command builders, PTY
transport command assembly, probes, run handles, installers) converge on:

```dart
class RemoteCommandSpec {
  final List<String> argv;
  final String? cwd;
  final Map<String, String>? env;
}
```

serialized by `RemoteCommandCodec`:

- legacy target (user-configured sshd profile): POSIX shell string — byte-for-
  byte identical to today's output (regression-guarded by tests)
- embedded target: `tp1:` + `jsonEncode(spec)` as the `exec` command string

The server rejects `exec` commands without the `tp1:` prefix. The **server**
injects the managed toolchain PATH at spawn time (it knows its own node/npm
locations), replacing the hardcoded POSIX `export PATH=…` in
`remote_flashskyai_command_builder.dart:6-7` which is wrong on Windows.

**host-info query.** `"tp1:" + {"query":"host-info"}` returns
`{"platform","osUser","elevated","inDocker","shell"}` as stdout, answered by
the server from Dart `Platform` plus self-inspection. `remoteSshRunsAsRoot` /
`remoteSshInDockerContainer` use this on embedded targets; the
dangerous-policy logic is unchanged (Windows `elevated` maps to
root-equivalent).

**Interactive shells.** The `shell` request carries no command; the server
spawns the OS-native shell on a flutter_pty. The phone's `_sshLaunchPlan`
sends no `/bin/bash` arguments for embedded targets.

**Versioning.** Offer bumps to `v: 2` with `emb: true`. v1 phones scanning a
v2 QR get a clean "unsupported version, upgrade" error (same release ships
both ends). `SshProfile` gains `embeddedTarget`, passed through by
`PairedProfileWriter`; the codec branches on it.

## App integration and data flow

**Startup sequence** (app start, same tier as relay registration):

1. Load or generate the ed25519 host key (`connect/host_key`, OpenSSH format
   via the fork's `SSHKeyPair`) — its SHA256 fingerprint is the offer's
   `hostKeyFingerprints`.
2. Load `ConnectSettingsStore.embeddedPort`; absent → pick a random high
   port and persist. On bind conflict → re-pick, re-persist, refresh a live
   offer, surface a non-blocking notice.
3. `EmbeddedSshServer.start()` binds the LAN interface on that port.

**Pairing flow** (QR skeleton unchanged):

```
desktop: offer(v2, emb, port=embeddedPort, fingerprints) --QR--> phone
phone:   POST /pair {token, deviceId, publicKey}
desktop: PairedDeviceStore.issueDevice(deviceId, publicKey)  // replaces
         authorized_keys writing; grant issuance unchanged
phone:   PairedProfileWriter persists profile {embeddedTarget: true, port,
         fingerprints}
```

**Relay.** `resolveRelayTarget('ssh')` returns the embedded server's loopback
port instead of the probed sshd port. Phone relay/tunnel logic is untouched.

**Connect UI.** `connectSshdDown` semantics become "embedded server failed to
start" (port conflict, etc.) with a retry affordance; the "Install OpenSSH
Server" hint is gone. The Windows firewall one-time prompt is documented.

**Stale profiles.** No migration. Connection failures detect port/fingerprint
mismatch and surface "the desktop has been upgraded — re-scan the pairing
code". Relay grants issued before the upgrade also stop authenticating (the
device public key lived only in `authorized_keys`, which is gone); the same
re-pair hint covers this path.

## Security model

- Keys enter `PairedDeviceStore` only via the pairing POST, gated by the
  invite token (10-minute TTL, invalidated on regenerate/stop).
- Revocation (`revokeDevice`) fails the next auth and tears down established
  channels for that device immediately.
- Host key pinned by the phone via the QR out-of-band channel (same trust
  model as today).
- Loopback-only forwarding binds; relay grants keep the existing SHA-256
  digest + constant-time comparison.
- Structured exec has no shell → no injection by construction.
- No key material in logs; auth failures go to `AppLogger`.

## Error handling

| Scenario | Behavior |
|---|---|
| Port occupied | re-pick + persist + refresh live offer + non-blocking notice |
| Firewall blocks LAN | listener bound, LAN unreachable — existing honest LAN/remote status labels apply |
| Host key file corrupt | regenerate; stale profile fingerprints mismatch → re-pair hint |
| Per-connection protocol error | disconnect that connection only; listener unaffected |
| v1 phone scans v2 QR | clean "unsupported version" error |
| Old profile connect failure | mismatch detection → "re-scan" hint |

## Testing

**tp_sshd (pure Dart VM) — dual tests as the core strategy**: every
capability is asserted through the vendored `dartssh2` client over a real
socket:

- handshake / KEX / strict-KEX / rekey; valid-key auth, wrong-key reject,
  revoked-key reject, throttling
- structured exec (argv/env/cwd/exit code), host-info query, PTY (echo,
  window-change, signal)
- SFTPv3 round trips (open/read/write/stat/readdir/rename/mkdir/delete,
  Windows path-context variant)
- tcpip-forward (bind/connect/byte pump/cancel), concurrent channels
- malformed packets → correct disconnect, listener survives

**App layer**: `RemoteCommandCodec` both branches (legacy output
byte-identical — regression guard); offer v2 encode/decode round trip;
`PairedProfileWriter` passthrough; `PairedDeviceStore.validateDevice`;
`ConnectAgent` new state machine.

**Integration** (`@Tags(['integration'])`): full pairing loop —
`EmbeddedSshServer` + pairing client + dartssh2 login + exec.

**Manual matrix**: Windows real-device QR pairing end-to-end; macOS
regression confirming no system-sshd residue.
