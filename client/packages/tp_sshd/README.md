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
  supported (verified against the fork's `SSHClient.rekey()`).

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
| `bindServerSocket` | `tcpip-forward` binds (loopback addresses only; unset refuses forwarding outright) |

An unset seam refuses its surface — nothing falls back to running real
commands or binding real sockets. The one bounded wait in the package:
`SSHServerChannel.close` gives data still queued for the client's window
credit two seconds to flush before dropping the tail.

See [test/dual_test_utils.dart](test/dual_test_utils.dart) for a complete
wiring example (in-memory socket pairs, a real `SSHClient` on the other end,
and raw-transport harnesses for protocol-level traffic).
