# tp_sshd

Pure-Dart SSH server for TeamPilot's embedded desktop server. Built on the
dartssh2 protocol primitives ([../dartssh2](../dartssh2) `protocol.dart`).

## Surface

- **Auth:** publickey only (ssh-ed25519 device keys), fail-closed, 6-attempt
  throttle, 30 s pre-auth timeout. The trust decision is always the
  embedder's `authenticate` callback; the signature is always verified first.
- **Channels:** session channels (structured `tp1:` exec + interactive
  shell/pty + the `sftp` subsystem) and remote port forwarding
  (`tcpip-forward`, loopback binds only). At most 10 simultaneously open
  channels per connection (OpenSSH's default; excess opens are refused with
  reason 4, resource shortage).
- **KEX:** curve25519-sha256, ed25519 host keys, chacha20-poly1305 /
  aes256-gcm, strict KEX (RFC 9142). Peer-initiated mid-session rekey is
  supported (verified against the fork's `SSHClient.rekey()`), and the
  server initiates rekeying itself: after `rekeyBytes` (default 1 GiB) of
  outbound traffic or `rekeyInterval` (default 1 h) of authenticated
  session lifetime, whichever comes first. Open channels survive the
  rotation. Both knobs are nullable — `null` disables that trigger. (The
  defaults are a deliberate divergence: OpenSSH 10.2's default is no
  configured `RekeyLimit` at all — its geometry-scale bound effectively
  never fires, which for a long-lived pairing session means keys that never
  rotate. See `SSHServerConfig.rekeyBytes` for the full rationale.)

## Usage

```dart
final server = await SSHServer.bind(
  connectionIterator,
  config: SSHServerConfig(hostKeyPair: hostKey, authenticate: ...),
);
```

`SSHServer` does not own listening: `bind` consumes already-accepted
`SSHSocket`s from a `StreamIterator`, so the embedder decides whether they
come from a real `ServerSocket` (dart:io), a WebSocket bridge, or an
in-memory test pair. A stream error is contained — it surfaces on
`SSHServer.done` after every live connection has been torn down, instead of
escaping as an unhandled zone error.

Everything the server executes is injected:

| Seam | Serves |
|------|--------|
| `processFactory` | structured `exec` requests (the `tp1:` argv/cwd/env grammar; no shell ever sees a command line) |
| `ptyFactory` | interactive `shell` requests (a prior `pty-req` is required) |
| `hostInfo` | the `tp1:` host-info query (answered by the server, never by spawning) |
| `sftpFileSystem` | the `sftp` subsystem (SFTPv3 over an injected filesystem) |
| `SSHForwardingConfig` | both forwarding directions: `allowTcpForwarding` (yes/all/no/local/remote mask) + `permitOpen` (per-target predicate) gate first, then `dialSocket` for `direct-tcpip` dials and `bindServerSocket` for `tcpip-forward` binds (loopback only), bounded by `dialTimeout`; `null` refuses both directions outright |

`direct-tcpip` open semantics follow OpenSSH: reason 1 (`administratively
prohibited`) for a disabled/refused/port-out-of-range target, reason 2
(`connect failed`) when the dial or its timeout fails; in both cases only the
channel is refused — the SSH connection stays alive. A successful dial
registers and confirms the channel before its pump starts.

An unset seam refuses its surface — nothing falls back to running real
commands or binding real sockets. The one bounded wait in the package:
`SSHServerChannel.close` gives data still queued for the client's window
credit two seconds to flush before dropping the tail.

Channel input is flow-controlled like OpenSSH's: the receive window granted
to the peer is only re-granted as the consumer takes bytes off
`SSHServerChannel.input`, reported through `SSHServerChannel.consumeInput`.
The in-package consumers (the exec/shell stdin pump, the SFTP subsystem,
the forwarding pump) report consumption with OS-level backpressure — each
write is awaited, so a program or socket that stops reading stops the
credit from returning. A peer that keeps sending past the granted window
beyond a 10% grace margin is disconnected (`channel N: peer ignored channel
window`, reason 2). Embedders subscribing to `input` directly should report
consumption the same way, or the peer's window will not refill.

See [test/dual_test_utils.dart](test/dual_test_utils.dart) for a complete
wiring example (in-memory socket pairs, a real `SSHClient` on the other end,
and raw-transport harnesses for protocol-level traffic).
