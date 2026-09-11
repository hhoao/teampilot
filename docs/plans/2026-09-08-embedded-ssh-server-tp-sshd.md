# Embedded SSH Server — tp_sshd Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `tp_sshd`, a pure-Dart SSH server package (plus additive server-role KEX support in the dartssh2 fork), fully dual-tested against the vendored dartssh2 client.

**Architecture:** The dartssh2 submodule gains a `protocol.dart` public export and server-role ECDH key-exchange completion inside `SSHTransport` (role-aware infrastructure already exists: `isServer` algorithm selection, directional key derivation, KEXINIT responder behavior). On top of that, a new in-repo package `client/packages/tp_sshd` implements the service layers — publickey userauth, connection/channel multiplexing, session channels (structured `tp1:` exec, shell/pty), SFTPv3 subsystem, and tcpip-forward — with every subsystem injectable (socket, process, pty, filesystem, bind factories) and dual-tested through the real dartssh2 client.

**Tech Stack:** Dart (VM only), dartssh2 fork (`client/packages/dartssh2`, submodule → https://github.com/hhoao/dartssh2.git), package:test.

**Spec:** `docs/specs/2026-09-08-embedded-ssh-server-design.md` — this plan implements the "Protocol server (tp_sshd)" section and the fork-export prerequisite. App integration (EmbeddedSshServer, offer v2, RemoteCommandCodec, UI) is a separate follow-up plan.

## Global Constraints

- **dartssh2 is a git submodule.** Tasks 1–2 commit inside `client/packages/dartssh2` (its own repo, branch `main` on hhoao/dartssh2). Push it before the parent repo bumps the pointer (Task 10). The parent repo only ever records a submodule pointer bump.
- **tp_sshd is pure Dart.** No Flutter, no `dart:ui`, no app imports. It must stay testable with `dart test` alone.
- **Test commands:** inside `client/packages/dartssh2` and `client/packages/tp_sshd`, run `dart analyze` and `dart test <path> --plain-name <name>`. (The repo-wide `dart run tool/run_tests.dart` wrapper governs the Flutter app suite; pure-Dart packages run `dart test` directly, matching the fork's existing CI.)
- **Fork changes are additive or role-guarded.** Anything new in `SSHTransport` runs only under `isServer == true`; client behavior must not change (existing fork tests must stay green untouched).
- **Algorithm surface (spec):** KEX `curve25519-sha256` + `curve25519-sha256@libssh.org`; host key `ssh-ed25519` only; ciphers `chacha20-poly1305@openssh.com`, `aes256-gcm@openssh.com`; MAC `hmac-sha256` (for non-AEAD negotiation paths). Device keys accepted: `ssh-ed25519` only.
- **Auth is fail-closed:** publickey only, max 6 attempts per connection, then disconnect. No password/keyboard-interactive ever advertised.
- **Exec accepts only structured payloads:** command strings must start with `tp1:`; anything else is a channel failure.
- **Fork style:** follow the existing dartssh2 code style (2-space indent, `printDebug?.call` traces on every handler, `SSHStateError` for role violations).

## File Structure

```
client/packages/dartssh2 (submodule)
  lib/protocol.dart                                  [Task 1] public protocol export
  lib/src/ssh_transport.dart                         [Task 2] server-role ECDH KEX completion
  test/src/ssh_transport_server_kex_test.dart        [Task 2] dual-transport handshake test

client/packages/tp_sshd (new in-repo package)
  pubspec.yaml                                       [Task 3]
  lib/tp_sshd.dart                                   [Task 3] public API export
  lib/src/ssh_server.dart                            [Task 3] SSHServer.bind + accept loop + config
  lib/src/server_connection.dart                     [Task 3/5] per-connection state machine
  lib/src/server_userauth.dart                       [Task 4] publickey service + throttle
  lib/src/server_channel.dart                        [Task 5] channel table + mux
  lib/src/server_session.dart                        [Task 6/7] session channel requests
  lib/src/server_process.dart                        [Task 6] process/pty abstractions + tp1 codec
  lib/src/server_sftp.dart                           [Task 8] SFTPv3 subsystem
  lib/src/sftp_filesystem.dart                       [Task 8] injected FS interface
  lib/src/server_forward.dart                        [Task 9] tcpip-forward + forwarded-tcpip
  test/test_socket_pair.dart                         [Task 3] in-memory SSHSocket pair helper
  test/dual_test_utils.dart                          [Task 3] client+server harness
  test/server_*_test.dart                            [Tasks 3–9] dual tests per subsystem
  README.md                                          [Task 10]
```

---

### Task 1: Fork — `protocol.dart` export library

**Files:**
- Create: `client/packages/dartssh2/lib/protocol.dart`
- Test: `client/packages/dartssh2/test/src/protocol_library_test.dart`

**Interfaces:**
- Consumes: existing `lib/src/` implementation libraries (unchanged).
- Produces: `import 'package:dartssh2/protocol.dart';` exposing `SSHMessageReader`, `SSHMessageWriter`, `SSH_Message_*` classes, `SSHKexUtils`, `SSHKexX25519`, `SSHEd25519PublicKey`, `SSHEd25519Signature`, `SSHAlgorithms`, algorithm type enums. All later tp_sshd imports of fork internals go through this library only.

- [ ] **Step 1: Write the failing test**

```dart
// test/src/protocol_library_test.dart
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:dartssh2/protocol.dart';
import 'package:test/test.dart';

void main() {
  test('protocol library exposes codec primitives for server use', () {
    final writer = SSHMessageWriter();
    writer.writeUint8(SSH_Message_Channel_Data.messageId);
    writer.writeUint32(4);
    writer.writeBytes(Uint8List.fromList('data'.codeUnits));
    final payload = writer.takeBytes();

    final reader = SSHMessageReader(payload);
    expect(reader.readMessageId(), SSH_Message_Channel_Data.messageId);
    expect(reader.readUint32(), 4);
    expect(reader.readString(), 'data');
  });

  test('exchange-hash helper is reachable through the protocol library', () {
    // Presence check: the server transport calls this with role-swapped
    // arguments; it must be importable without src/ paths.
    expect(SSHKexUtils.computeExchangeHash, isNotNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/dartssh2 && dart test test/src/protocol_library_test.dart`
Expected: FAIL — `Error: Cannot find "package:dartssh2/protocol.dart"`.

- [ ] **Step 3: Write the export library**

```dart
// lib/protocol.dart
/// Protocol primitives shared by the SSH client and third-party server
/// implementations.
///
/// Additive public surface on top of the implementation libraries that
/// [dartssh2.dart] has always exported. Nothing here changes behavior; it
/// only makes the wire codec, key-exchange math, and algorithm registries
/// importable by the tp_sshd server package without reaching into `src/`.
library;

export 'src/ssh_message.dart';
export 'src/ssh_packet.dart';
export 'src/ssh_algorithm.dart';
export 'src/ssh_kex_utils.dart';
export 'src/algorithm/ssh_cipher_type.dart';
export 'src/algorithm/ssh_hostkey_type.dart';
export 'src/algorithm/ssh_kex_type.dart';
export 'src/algorithm/ssh_mac_type.dart';
export 'src/kex/kex_x25519.dart';
export 'src/hostkey/hostkey_ed25519.dart';
export 'src/message/msg_channel.dart';
export 'src/message/msg_debug.dart';
export 'src/message/msg_disconnect.dart';
export 'src/message/msg_ext_info.dart';
export 'src/message/msg_ignore.dart';
export 'src/message/msg_kex.dart';
export 'src/message/msg_kex_dh.dart';
export 'src/message/msg_kex_ecdh.dart';
export 'src/message/msg_request.dart';
export 'src/message/msg_service.dart';
export 'src/message/msg_unimplemented.dart';
export 'src/message/msg_userauth.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client/packages/dartssh2 && dart test test/src/protocol_library_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Guard against client regressions**

Run: `cd client/packages/dartssh2 && dart analyze && dart test`
Expected: analyze clean; full fork suite green (network-dependent tests may skip without fixtures — same skip behavior as before this change).

- [ ] **Step 6: Commit (inside the submodule)**

```bash
cd client/packages/dartssh2
git add lib/protocol.dart test/src/protocol_library_test.dart
git commit -m "feat: add protocol.dart public export for server implementations"
```

---

### Task 2: Fork — server-role ECDH key exchange in SSHTransport

**Files:**
- Modify: `client/packages/dartssh2/lib/src/ssh_transport.dart` (dispatch switch near line 1550; new handler after `_handleMessageKexReply` ~line 1935)
- Test: `client/packages/dartssh2/test/src/ssh_transport_server_kex_test.dart`

**Interfaces:**
- Consumes: `SSHKexUtils.computeExchangeHash`, `SSHKexX25519.computeSecret`, `SSH_Message_KexECDH_Init/Reply`, `SSHKeyPair.sign/toPublicKey` (all existing).
- Produces: `SSHTransport(socket, isServer: true, hostKeyPair: pair)` — new optional constructor parameter `final SSHKeyPair? hostKeyPair;` (required for a server to complete KEX; a server without one fails the exchange with `SSHStateError`). Client behavior unchanged (`hostKeyPair` ignored when `isServer == false`).

Background for the implementer — what already works server-side in `SSHTransport`: algorithm selection honors `isServer` (`SSHKexUtils.selectAlgorithm`, RFC 4253 §7.1 server-picks-client's-first rule), directional cipher/MAC key application has `isClient` branches, `_handleMessageKexInit` already responds with the server's own KEXINIT and negotiates, and strict-KEX server indicators (`kex-strict-s-v00@openssh.com`) are advertised. What is missing: nothing ever handles the client's `SSH_MSG_KEXDH_INIT` (message id 30) on the server side — `_handleMessageKexReply` throws `SSHStateError('Unexpected KEX_REPLY')` for id 31, and id 30 is simply not dispatched.

- [ ] **Step 1: Write the failing test**

The test mirrors the client path `_handleMessageKexReply` (lines 1815–1935) with roles swapped: server computes the shared secret from the client's ephemeral key, signs the exchange hash with the host key, replies KEX_ECDH_REPLY + NEWKEYS. The client (a real `SSHTransport`) must verify our signature through its existing `_verifyHostkey` path — proving role-correctness of the hash inputs without trusting our own implementation.

```dart
// test/src/ssh_transport_server_kex_test.dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/socket/ssh_socket.dart';
import 'package:test/test.dart';

/// Minimal paired in-memory SSHSocket. Each end's sink writes are delivered
/// to the other end's stream.
class _LoopbackSSHSocket implements SSHSocket {
  _LoopbackSSHSocket._(this._peer);

  static (_LoopbackSSHSocket, _LoopbackSSHSocket) pair() {
    late final _LoopbackSSHSocket a;
    late final _LoopbackSSHSocket b;
    a = _LoopbackSSHSocket._(b);
    b = _LoopbackSSHSocket._(a);
    return (a, b);
  }

  final _LoopbackSSHSocket _peer;
  final _controller = StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get stream => _controller.stream;

  @override
  StreamSink<List<int>> get sink =>
      _peer._controller.sink as StreamSink<List<int>>;

  @override
  Future<void> get done => _controller.done;

  @override
  Future<void> close() async {
    await _peer._controller.sink.close();
  }

  @override
  void destroy() {
    _peer._controller.sink.close();
  }
}

void main() {
  test('server transport completes ECDH kex and reaches encrypted state', () async {
    final hostKey = SSHKeyPair.fromPem(
      '''-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACB0LbA5uHcFpizorSDX2FfRyEDQZl6iiWk6ZclIvfDcXfJQgAAAEg0LavWNC2
r1gAAAAtzc2gtZWQyNTUxOQAAACB0LbA5uHcFpizorSDX2FfRyEDQZl6iiWk6ZclIvfDcXfJQ
gAAAEAxJ1RdCjm0wi5cT7KF80XLfjnBQCDyKcNqWyy+i9DTpUYUfwGFXBUtNADLLCGf
-----END OPENSSH PRIVATE KEY-----''',
    ).single;

    final (clientSocket, serverSocket) = _LoopbackSSHSocket.pair();
    var hostKeySeen = false;
    final client = SSHTransport(
      clientSocket,
      onVerifyHostKey: (type, fingerprint) {
        hostKeySeen = true;
        return true;
      },
    );
    final server = SSHTransport(serverSocket, isServer: true, hostKeyPair: hostKey);

    // SSH_Message_Ignore is RFC 4253 §11 valid filler after NEWKEYS; sending
    // it in both directions proves the encrypted channel is up in both ways.
    final clientEchoed = Completer<void>();
    server.onMessage = (payload) {
      if (SSHMessage.readMessageId(payload) == SSH_Message_Ignore.messageId) {
        if (!clientEchoed.isCompleted) clientEchoed.complete();
      }
      return true;
    };
    final serverEchoed = Completer<void>();
    client.onMessage = (payload) {
      if (SSHMessage.readMessageId(payload) == SSH_Message_Ignore.messageId) {
        if (!serverEchoed.isCompleted) serverEchoed.complete();
      }
      return true;
    };

    await clientEchoed.future.timeout(const Duration(seconds: 5));
    await serverEchoed.future.timeout(const Duration(seconds: 5));
    expect(hostKeySeen, isTrue,
        reason: 'client must verify the server host key signature');
    expect(client.isClosed, isFalse);
    expect(server.isClosed, isFalse);

    client.close();
    server.close();
  });

  test('server transport refuses kex without a host key', () async {
    final (clientSocket, serverSocket) = _LoopbackSSHSocket.pair();
    final server = SSHTransport(serverSocket, isServer: true);
    SSHTransport(clientSocket); // drive the handshake
    expect(
      server.done,
      throwsA(isA<SSHStateError>()),
    );
  });
}
```

Note: the test PEM above must be replaced by a real throwaway ed25519 key generated during implementation (`ssh-keygen -t ed25519 -f /tmp/tp_test_key -N ''`), embedded verbatim. Never embed a key used anywhere else.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/dartssh2 && dart test test/src/ssh_transport_server_kex_test.dart`
Expected: first test FAILS (timeout — client's `onVerifyHostKey` never fires because no KEX_REPLY ever arrives); second may pass vacuously or fail on error type.

- [ ] **Step 3: Implement the server-side KEX path**

In `ssh_transport.dart`:

1. Add the constructor parameter and field:

```dart
  /// Private key used to sign the exchange hash when [isServer] is true.
  /// Required for a server to complete the key exchange.
  final SSHKeyPair? hostKeyPair;
```

(wire it through the constructor's initializer list alongside `isServer`).

2. Add message id 30 to the dispatch switch in `_handleMessage`. `SSH_Message_KexDH_Init` and `SSH_Message_KexECDH_Init` share message id 30; the negotiated `_kexType` decides the encoding. Server-side we only support the ECDH family (the narrow algorithm surface), so:

```dart
      case SSH_Message_KexECDH_Init.messageId:
        if (isServer) return _handleMessageKexEcdhInit(message);
        throw SSHStateError('Unexpected KEXDH_INIT');
```

Also verify `_isForbiddenDuringStrictKex` does not forbid id 30 during the exchange (it must not — it is *the* expected message; only filler like IGNORE/DEBUG is forbidden).

3. Implement the handler, mirroring `_handleMessageKexReply` (lines 1815–1935) with every client/server role inverted:

```dart
  /// Server side of the elliptic-curve key exchange: compute the shared
  /// secret from the client's ephemeral public key, sign the exchange hash
  /// with the host key, and answer KEX_ECDH_REPLY followed by NEWKEYS.
  /// (RFC 5656 §4 / draft-ietf-secsh-ecdh for curve25519 via SSHKexX25519.)
  Future<void> _handleMessageKexEcdhInit(Uint8List payload) async {
    printDebug?.call('SSHTransport._handleMessageKexEcdhInit');
    if (!isServer) throw SSHStateError('Unexpected KEXDH_INIT');

    final kex = _kex;
    if (kex is! SSHKexECDH) {
      throw SSHStateError('No ECDH key exchange algorithm negotiated');
    }
    final hostKeyPair = this.hostKeyPair;
    if (hostKeyPair == null) {
      throw SSHStateError('Server transport requires a hostKeyPair');
    }

    final message = SSH_Message_KexECDH_Init.decode(payload);
    printTrace?.call('<- $socket: $message');
    final sharedSecret = kex.computeSecret(message.publicKey);

    final exchangeHash = SSHKexUtils.computeExchangeHash(
      digest: _kexType!.createDigest(),
      clientVersion: _remoteVersion!,
      serverVersion: _localVersion,
      clientKexInit: _remoteKexInit,
      serverKexInit: _localKexInit,
      hostKey: hostKeyPair.toPublicKey().encode(),
      clientPublicKey: message.publicKey,
      serverPublicKey: kex.publicKey,
      sharedSecret: sharedSecret,
    );

    _exchangeHash = exchangeHash;
    _sessionId ??= exchangeHash;
    _sharedSecret = sharedSecret;

    sendPacket(
      SSH_Message_KexECDH_Reply(
        hostPublicKey: hostKeyPair.toPublicKey().encode(),
        ecdhPublicKey: kex.publicKey,
        signature: hostKeyPair.sign(exchangeHash).encode(),
      ).encode(),
    );
    printTrace?.call('-> $socket: SSH_Message_KexECDH_Reply');

    _sendNewKeys();
    _applyLocalKeys();
    onReady?.call();
  }
```

Notes for the implementer:
- `kex.computeSecret(message.publicKey)` — same call the client makes at line 1857; X25519 scalar multiplication is symmetric.
- `SSHKexECDH` is the existing supertype (see `_sendKexDHInit`, line 1479). Import it if the file does not already.
- If `SSH_Message_KexECDH_Reply`'s constructor parameter names differ (check `src/message/msg_kex_ecdh.dart:37`), use the real names — the semantics are host key blob, server ephemeral public, signature blob.
- If `SSHSignature.encode()` returns the `string alg || string sig` wrapper expected on the wire, use it directly; if the reply wants the raw wrapper built via `SSHMessageWriter`, mirror whatever `_verifyHostkey` consumes.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client/packages/dartssh2 && dart test test/src/ssh_transport_server_kex_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Guard client behavior**

Run: `cd client/packages/dartssh2 && dart analyze && dart test`
Expected: analyze clean, full suite green — especially `ssh_transport_strict_kex_test.dart`, `ssh_transport_aead_test.dart`, `ssh_transport_hardening_test.dart`.

- [ ] **Step 6: Commit (inside the submodule)**

```bash
cd client/packages/dartssh2
git add lib/src/ssh_transport.dart test/src/ssh_transport_server_kex_test.dart
git commit -m "feat: complete server-role ECDH key exchange in SSHTransport"
```

---

### Task 3: tp_sshd scaffold — SSHServer.bind, connection lifecycle, fail-closed auth state

**Files:**
- Create: `client/packages/tp_sshd/pubspec.yaml`
- Create: `client/packages/tp_sshd/lib/tp_sshd.dart`
- Create: `client/packages/tp_sshd/lib/src/ssh_server.dart`
- Create: `client/packages/tp_sshd/lib/src/server_connection.dart`
- Test: `client/packages/tp_sshd/test/test_socket_pair.dart`
- Test: `client/packages/tp_sshd/test/dual_test_utils.dart`
- Test: `client/packages/tp_sshd/test/server_handshake_test.dart`

**Interfaces:**
- Consumes: `SSHTransport(socket, isServer: true, hostKeyPair:)`, `sendPacket`, `onMessage` (fork, Tasks 1–2); `SSHClient(socket, username:, onVerifyHostKey:, identities:)`.
- Produces (used by Tasks 4–9 and the later app integration plan):

```dart
class SSHServerConfig {
  SSHServerConfig({
    required this.hostKeyPair,
    required this.authenticate,
    this.authTimeout = const Duration(seconds: 30),
    this.maxAuthAttempts = 6,
    this.printDebug,
    this.printTrace,
  });
  final SSHKeyPair hostKeyPair;
  final Future<bool> Function(SSHServerAuthRequest request) authenticate;
  final Duration authTimeout;
  final int maxAuthAttempts;
  final void Function(String? message)? printDebug;
  final void Function(String? message)? printTrace;
}

class SSHServerAuthRequest {
  final String username;
  final String algorithm; // always 'ssh-ed25519'
  final Uint8List publicKey; // OpenSSH wire blob
}

class SSHServer {
  static Future<SSHServer> bind(
    StreamIterator<SSHSocket> connections, {
    required SSHServerConfig config,
  });
  Future<void> close();
  int get activeConnections;
}

/// The narrow algorithm surface from the spec, as an SSHAlgorithms value.
const SSHAlgorithms tpServerAlgorithms = SSHAlgorithms(
  kex: [SSHKexType.x25519Rfc, SSHKexType.x25519],
  hostkey: [SSHHostkeyType.ed25519],
  cipher: [SSHCipherType.chacha20poly1305, SSHCipherType.aes256gcm],
  mac: [SSHMacType.hmacSha256],
);
```

`SSHServer.bind` takes a `StreamIterator<SSHSocket>` instead of a port: the app decides how to listen (real ServerSocket, tests use in-memory pairs). Each accepted socket gets an `SSHServerConnection` running `SSHTransport(socket, isServer: true, hostKeyPair: config.hostKeyPair, algorithms: tpServerAlgorithms, onMessage: ...)` with an auth timeout; a connection that never authenticates is closed. Task 3's connection layer understands only `SSH_Message_Service_Request` (accepts `ssh-userauth`) and drops everything else with `SSH_MSG_UNIMPLEMENTED` — authentication arrives in Task 4, so at this point every `SSHClient` connect must fail auth cleanly.

- [ ] **Step 1: Create pubspec + export**

```yaml
# pubspec.yaml
name: tp_sshd
description: Pure-Dart SSH server for TeamPilot's embedded desktop server.
version: 0.1.0
publish_to: none

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  dartssh2:
    path: ../dartssh2

dev_dependencies:
  lints: ">=4.0.0 <7.0.0"
  test: ^1.25.15
```

```dart
// lib/tp_sshd.dart
export 'package:dartssh2/protocol.dart'
    show SSHAlgorithms, SSHKexType, SSHHostkeyType, SSHCipherType, SSHMacType;
export 'src/ssh_server.dart';
```

- [ ] **Step 2: Write the failing test**

Move `_LoopbackSSHSocket` from Task 2's test into `test/test_socket_pair.dart` as a public helper (`loopbackSSHSocketPair()`, returns `(SSHSocket, SSHSocket)`).

```dart
// test/dual_test_utils.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'test_socket_pair.dart';

/// Starts an SSHServer over a fresh in-memory socket pair and returns a
/// connected, host-key-accepting SSHClient plus the server.
Future<(SSHClient, SSHServer)> startDualPair({
  required SSHKeyPair hostKeyPair,
  required Future<bool> Function(SSHServerAuthRequest request) authenticate,
  List<SSHKeyPair> clientIdentities = const [],
  String username = 'user',
}) async {
  final (clientSocket, serverSocket) = loopbackSSHSocketPair();
  final connections = StreamController<SSHSocket>();
  final server = await SSHServer.bind(
    StreamIterator(connections.stream),
    config: SSHServerConfig(
      hostKeyPair: hostKeyPair,
      authenticate: authenticate,
    ),
  );
  connections.add(serverSocket);
  final client = SSHClient(
    clientSocket,
    username: username,
    onVerifyHostKey: (_, __) => true,
    identities: clientIdentities,
  );
  await client.authenticated; // throws on auth failure — callers rely on that
  return (client, server);
}

/// A throwaway ed25519 keypair for tests (public key in OpenSSH wire format
/// via `.toPublicKey().encode()`).
final testDeviceKey = SSHKeyPair.fromPem(<the throwaway PEM embedded here>);
final testHostKey = SSHKeyPair.fromPem(<the throwaway PEM embedded here>);
```

```dart
// test/server_handshake_test.dart
@TestOn('vm')
library;

import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';

void main() {
  test('client handshake reaches auth and fails closed without userauth', () async {
    final (clientSocket, serverSocket) = loopbackSSHSocketPair();
    final connections = StreamController<SSHSocket>();
    final server = await SSHServer.bind(
      StreamIterator(connections.stream),
      config: SSHServerConfig(
        hostKeyPair: testHostKey,
        authenticate: (_) async => false,
      ),
    );
    connections.add(serverSocket);
    final client = SSHClient(
      clientSocket,
      username: 'user',
      onVerifyHostKey: (_, __) => true,
    );
    // No identities, and the server has no userauth service yet: the
    // connection must terminate with an auth failure, not hang or crash.
    await expectLater(
      client.authenticated,
      throwsA(isA<Exception>()),
    );
    expect(server.activeConnections, greaterThanOrEqualTo(0));
    await server.close();
  });

  test('auth timeout closes silent connections', () async {
    final (clientSocket, serverSocket) = loopbackSSHSocketPair();
    final connections = StreamController<SSHSocket>();
    final server = await SSHServer.bind(
      StreamIterator(connections.stream),
      config: SSHServerConfig(
        hostKeyPair: testHostKey,
        authenticate: (_) async => false,
        authTimeout: const Duration(milliseconds: 150),
      ),
    );
    connections.add(serverSocket);
    // Client transport that never sends a service request after kex.
    final transport = SSHTransport(clientSocket);
    await expectLater(
      transport.done.timeout(const Duration(seconds: 2)),
      completes,
    );
    await server.close();
    transport.close();
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd client/packages/tp_sshd && dart test`
Expected: FAIL — package does not exist / imports unresolved.

- [ ] **Step 4: Implement `ssh_server.dart` and `server_connection.dart`**

```dart
// lib/src/ssh_server.dart
import 'dart:async';

import 'package:dartssh2/protocol.dart';
import 'package:dartssh2/dartssh2.dart' show SSHKeyPair, SSHSocket;

import 'server_connection.dart';

/// The narrow negotiation surface advertised by tp_sshd servers (spec:
/// x25519 KEX, ed25519 host keys, AEAD ciphers).
const SSHAlgorithms tpServerAlgorithms = SSHAlgorithms(
  kex: [SSHKexType.x25519Rfc, SSHKexType.x25519],
  hostkey: [SSHHostkeyType.ed25519],
  cipher: [SSHCipherType.chacha20poly1305, SSHCipherType.aes256gcm],
  mac: [SSHMacType.hmacSha256],
);

class SSHServer { /* bind(StreamIterator<SSHSocket>, {config}) … */ }
class SSHServerConfig { /* fields per Interfaces block above */ }
class SSHServerAuthRequest { /* username, algorithm, publicKey */ }
```

Implementation shape: `bind` advances the `StreamIterator` in a loop; each socket spawns an `SSHServerConnection(socket, config)` whose `SSHTransport` is created with `isServer: true`, the host key pair, `tpServerAlgorithms`, and `onMessage` forwarding to the connection state machine. `close()` stops the loop and closes live connections. `activeConnections` counts them.

`server_connection.dart` at this stage: a state machine with an enum `_Phase { auth, running, closed }`, a `Timer(config.authTimeout)` that destroys the socket unless auth completed, and an `onMessage` handler that:
- `SSH_Message_Service_Request.messageId` (6) → if `service == 'ssh-userauth'` reply `SSH_Message_Service_Accept`; anything else → disconnect with `SSH_DISCONNECT_SERVICE_NOT_AVAILABLE` (2).
- any other message id → return `false` (transport answers SSH_MSG_UNIMPLEMENTED) — in `_Phase.auth`. (Task 5 replaces the `_Phase.running` branch.)

Run: `cd client/packages/tp_sshd && dart test`
Expected: PASS (2 tests).

- [ ] **Step 5: Analyze and commit**

```bash
cd client/packages/tp_sshd && dart analyze
cd /c/Users/haung/git/teampilot
git add client/packages/tp_sshd
git commit -m "feat(tp_sshd): server scaffold with fail-closed connection lifecycle"
```

---

### Task 4: tp_sshd — publickey userauth with signature enforcement and throttling

**Files:**
- Create: `client/packages/tp_sshd/lib/src/server_userauth.dart`
- Modify: `client/packages/tp_sshd/lib/src/server_connection.dart` (wire userauth into `_Phase.auth`)
- Test: `client/packages/tp_sshd/test/server_userauth_test.dart`

**Interfaces:**
- Consumes: `SSHServerConfig.authenticate`, `SSH_Message_Userauth_Request/Failure/Success/PK_Ok`, `SSHEd25519PublicKey`.
- Produces: `Future<bool> verifyUserauthSignature(...)` internals used by the connection; behavior contract consumed by Tasks 5–9 (a connection only reaches `running` after `authenticate` returned true AND the ed25519 signature over the RFC 4252 §7 blob verified).

RFC 4252 §7 wire contract the implementer must reproduce exactly (this is the blob the dartssh2 client signs — see `ssh_client.dart:1195-1230`):

```
string    session identifier
byte      SSH_MSG_USERAUTH_REQUEST (50)
string    user name
string    service name
string    "publickey"
boolean   TRUE
string    public key algorithm name
string    public key blob
```

The signature field in the request is `string sig-alg || string signature bytes`. Public-key *probing* (`boolean FALSE`, no signature) is answered with `SSH_Message_Userauth_PK_Ok` when the key is trusted — dartssh2 probes first (README: "RFC 4252 §7.8 public-key probing"), so without PK_Ok every real client auth fails.

- [ ] **Step 1: Write the failing tests**

```dart
// test/server_userauth_test.dart
@TestOn('vm')
library;

import 'package:dartssh2/dartssh2.dart';
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';

void main() {
  test('valid device key authenticates', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (req) async {
        expect(req.username, 'user');
        expect(req.algorithm, 'ssh-ed25519');
        expect(req.publicKey, testDeviceKey.toPublicKey().encode());
        return true;
      },
      clientIdentities: [testDeviceKey],
    );
    expect(client.authenticated, completes); // already awaited in helper
    await server.close();
    client.close();
  });

  test('untrusted key is rejected', () async {
    await expectLater(
      startDualPair(
        hostKeyPair: testHostKey,
        authenticate: (_) async => false,
        clientIdentities: [testDeviceKey],
      ),
      throwsA(anything),
    );
  });

  test('server enforces the signature, not just key trust', () async {
    // authenticate() returning true cannot bypass signature verification:
    // a client that never signs (disableHostkeyVerification-style probing
    // abuse) must not authenticate. dartssh2 always signs, so simulate the
    // attack by asserting the connection closes when the signature path is
    // fed garbage — covered by the malformed-auth test below.
  }, skip: 'covered by malformed request test');

  test('malformed userauth message disconnects the connection', () async {
    // Hand-rolled: connect a raw SSHTransport, complete kex, send a
    // USERAUTH_REQUEST with a truncated public key blob, expect disconnect.
  });
}
```

(For the malformed test, drive a raw `SSHTransport` against the server, as in Task 2's test, and inject a hand-encoded `SSH_Message_Userauth_Request` — construct via `SSHMessageWriter` with a deliberately short key blob.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client/packages/tp_sshd && dart test test/server_userauth_test.dart`
Expected: FAIL — valid-key test times out (no userauth service).

- [ ] **Step 3: Implement `server_userauth.dart`**

```dart
// lib/src/server_userauth.dart
import 'dart:typed_data';

import 'package:dartssh2/protocol.dart';
import 'package:dartssh2/dartssh2.dart' show SSHKeyPair;

/// Verifies the RFC 4252 §7 signature of a publickey USERAUTH_REQUEST.
/// [signedBlobPrefix] is the request re-encoded without the signature —
/// the connection layer builds it per the wire contract above, prepending
/// `string sessionId`.
bool verifyEd25519UserauthSignature({
  required Uint8List sessionId,
  required SSH_Message_Userauth_Request request,
}) {
  final writer = SSHMessageWriter();
  writer.writeBytes(sessionId);
  writer.writeUint8(SSH_Message_Userauth_Request.messageId);
  writer.writeUtf8(request.username);
  writer.writeUtf8(request.serviceName);
  writer.writeUtf8('publickey');
  writer.writeBool(true);
  writer.writeUtf8(request.publicKeyAlgorithm);
  writer.writeBytes(request.publicKey);
  final blob = writer.takeBytes();

  final sigReader = SSHMessageReader(request.signature);
  final sigAlg = sigReader.readString();
  final sigBytes = sigReader.readString();
  if (sigAlg != 'ssh-ed25519') return false;

  final keyReader = SSHMessageReader(request.publicKey);
  if (keyReader.readString() != 'ssh-ed25519') return false;
  final key = SSHEd25519PublicKey.decode(keyReader.readString());
  return key.verify(blob, SSHEd25519Signature(sigBytes));
}
```

(Adjust decode/verify call shapes to the real `SSHEd25519PublicKey` API in `src/hostkey/hostkey_ed25519.dart` — decode from the raw 32-byte key body, verify `(message, signature)`.)

Connection integration: in `_Phase.auth`, on `SSH_Message_Userauth_Request.messageId` (50):
- method != 'publickey' → `SSH_Message_Userauth_Failure` with no auth methods (fail closed: advertise nothing).
- probing request (`request.hasSignature == false`) → if `config.authenticate(...)` says trusted, reply `SSH_Message_Userauth_PK_Ok`; else failure.
- signed request → signature must verify (above) AND `authenticate` must return true → `SSH_Message_Userauth_Success`, cancel auth timer, phase = `running`; otherwise failure.
- Count failures; at `config.maxAuthAttempts` send `SSH_Message_Disconnect` (reason 14, `SSH_DISCONNECT_NO_MORE_AUTH_METHODS_AVAILABLE`) and destroy.
- `request.username` must equal the username the connection was offered — the app passes the expected username via a new `SSHServerConfig.expectedUsername` field (add it here; the later app plan wires the offer's username).

Run: `cd client/packages/tp_sshd && dart test`
Expected: PASS (all files).

- [ ] **Step 4: Analyze and commit**

```bash
cd client/packages/tp_sshd && dart analyze
cd /c/Users/haung/git/teampilot
git add client/packages/tp_sshd
git commit -m "feat(tp_sshd): publickey userauth with signature enforcement and throttling"
```

---

### Task 5: tp_sshd — connection layer: channel multiplexing + keepalive

**Files:**
- Create: `client/packages/tp_sshd/lib/src/server_channel.dart`
- Modify: `client/packages/tp_sshd/lib/src/server_connection.dart` (`_Phase.running` branch)
- Test: `client/packages/tp_sshd/test/server_channel_test.dart`

**Interfaces:**
- Consumes: `SSH_Message_Channel_*` classes, `SSH_Message_Global_Request`, `SSH_Message_Request_Success`.
- Produces (Tasks 6–9 build on these):

```dart
/// One open channel on the server side. Owns window accounting and the
/// confirm/failure lifecycle for locally-opened channels (forwarded-tcpip).
class SSHServerChannel {
  final int recipientChannel; // the client's channel number
  final int ourChannel;       // the number we assigned
  final String channelType;

  /// Data the client sends on this channel.
  Stream<Uint8List> get input;

  /// Extended data (stderr) the client sends.
  Stream<Uint8List> get extendedInput;

  /// Outgoing stdout/stderr/EOF/close. Window-adjust handled internally.
  void write(Uint8List data);
  void writeExtended(Uint8List data);
  void sendEof();
  void close();

  /// Delivered when the client requests this channel (e.g. session opened).
  Future<void> Function(SSHServerChannel channel)? onRequest;
}
```

- [ ] **Step 1: Write the failing test**

```dart
// test/server_channel_test.dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';

void main() {
  test('client can open a session channel', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
    );
    final session = await client.openSession();
    expect(session.localChannel, greaterThanOrEqualTo(0));
    client.close();
    await server.close();
  });

  test('unknown channel type gets open-failure', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
    );
    await expectLater(
      client.openChannel(
        SSH_Channel_Type('direct-tcpip'), // not supported at this task
      ),
      throwsA(anything),
    );
    client.close();
    await server.close();
  });

  test('keepalive global request is answered', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
    );
    // dartssh2's SSHClient.ping() sends keepalive@openssh.com and expects
    // a reply within the keepAliveInterval; a missing reply surfaces as a
    // keepalive failure that closes the client.
    await expectLater(client.ping(), completes);
    client.close();
    await server.close();
  });
}
```

(Use the real `SSHClient.openSession()`/`ping()` signatures from `ssh_client.dart`; the `openChannel` call shape may differ — check `SSHClient.openChannel`'s actual parameter type and mirror it.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client/packages/tp_sshd && dart test test/server_channel_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

`server_channel.dart`: a channel table (`Map<int, SSHServerChannel>` keyed by our channel number), each channel holding `StreamController`s for input/extendedInput, send-window bookkeeping (grant generous windows, reply `SSH_Message_Channel_Window_Adjust` when the client exhausts ours), and outgoing `write`/`writeExtended`/`sendEof`/`close` encoding `SSH_Message_Channel_Data/Extended_Data/EOF/Close` with the correct recipient id.

`server_connection.dart` `_Phase.running` dispatch:
- `SSH_Message_Channel_Open` (90) → `session` gets a channel + `SSH_Message_Channel_Confirmation`; other types → `SSH_Message_Channel_Open_Failure` (reason 3, admin prohibited).
- `SSH_Message_Channel_Window_Adjust` (93), `SSH_Message_Channel_Data` (94), `SSH_Message_Channel_Extended_Data` (95), `SSH_Message_Channel_EOF` (96), `SSH_Message_Channel_Close` (97) → route to channel by recipient id; unknown id → ignore (race with close).
- `SSH_Message_Channel_Request` (98) → forward to the channel's `onRequest` (session requests are Task 6/7).
- `SSH_Message_Global_Request` (80) → `keepalive@openssh.com` (wantsReply) → `SSH_Message_Request_Success`; `tcpip-forward`/`cancel-tcpip-forward` are Task 9 (failure until then); everything else → `SSH_Message_Request_Failure`.

Run: `cd client/packages/tp_sshd && dart test`
Expected: PASS.

- [ ] **Step 4: Analyze and commit**

```bash
cd client/packages/tp_sshd && dart analyze
cd /c/Users/haung/git/teampilot
git add client/packages/tp_sshd
git commit -m "feat(tp_sshd): channel multiplexing and keepalive"
```

---

### Task 6: tp_sshd — session exec: structured `tp1:` payload, process factory, host-info

**Files:**
- Create: `client/packages/tp_sshd/lib/src/server_process.dart`
- Create: `client/packages/tp_sshd/lib/src/server_session.dart`
- Modify: `client/packages/tp_sshd/lib/src/ssh_server.dart` (config: `onExec`, `processFactory`, `hostInfo`)
- Test: `client/packages/tp_sshd/test/server_exec_test.dart`

**Interfaces:**
- Consumes: `SSHServerChannel.onRequest` (Task 5), `SSH_Message_Channel_Request` fields (`wantReply`, `exec` command string).
- Produces:

```dart
/// A spawned process backing an exec channel. Implemented by the app with
/// flutter_pty / Process.run; faked in tests.
abstract class SSHServerProcess {
  Stream<Uint8List> get stdout;
  Stream<Uint8List> get stderr;
  StreamSink<List<int>> get stdin;
  Future<int> get exitCode;
  void kill();
}

typedef SSHProcessFactory =
    Future<SSHServerProcess?> Function(
      List<String> argv,
      String? cwd,
      Map<String, String> env,
    );

/// Answered by the app from Platform + self-inspection; faked in tests.
class SSHHostInfo {
  final String platform;    // 'windows' | 'macos' | 'linux'
  final String osUser;
  final bool elevated;
  final bool inDocker;
  final String shell;       // display name only
}

class SSHExecRequest {
  final List<String> argv;
  final String? cwd;
  final Map<String, String> env;
}

/// `tp1:` payload codec — the only exec grammar this server speaks.
class TpExecCodec {
  static const prefix = 'tp1:';
  static String encode(SSHExecRequest request);
  static SSHExecRequest? tryDecode(String command);
  static bool isHostInfoQuery(String command);
  static String encodeHostInfo(SSHHostInfo info);
}
```

Config additions (with defaults so earlier tests keep compiling): `SSHProcessFactory? processFactory`, `SSHHostInfo Function()? hostInfo`, both null → exec requests fail (channel failure).

- [ ] **Step 1: Write the failing tests**

```dart
// test/server_exec_test.dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';

/// Fake process echoing argv back on stdout with a configurable exit code.
class _EchoProcess implements SSHServerProcess {
  _EchoProcess(this.argv);
  final List<String> argv;
  final _stdin = StreamController<List<int>>();
  final _stdout = StreamController<Uint8List>();
  final _stderr = StreamController<Uint8List>();

  @override
  Future<int> get exitCode async => 17;

  @override
  void kill() {}

  @override
  StreamSink<List<int>> get stdin => _stdin.sink;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  void start() {
    _stdout.add(Uint8List.fromList(utf8.encode(argv.join(' '))));
    _stdout.close();
    _stderr.close();
  }
}

void main() {
  test('structured exec spawns argv and reports exit code', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      processFactory: (argv, cwd, env) async {
        expect(cwd, 'C:\\work\\demo');
        expect(env['TEAMPilot_TEST'], '1');
        final process = _EchoProcess(argv)..start();
        return process;
      },
    );
    final session = await client.execute(
      TpExecCodec.encode(const SSHExecRequest(
        argv: ['claude', '--version'],
        cwd: r'C:\work\demo',
        env: {'TEAMPilot_TEST': '1'},
      )),
    );
    final output = await utf8.decoder.bind(session.stdout).join();
    expect(output, 'claude --version');
    expect(await session.exitCode, 17);
    client.close();
    await server.close();
  });

  test('plain shell-string exec is rejected', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      processFactory: (argv, cwd, env) async => _EchoProcess(argv)..start(),
    );
    await expectLater(
      client.execute('rm -rf /'), // no tp1: prefix
      throwsA(anything),
    );
    client.close();
    await server.close();
  });

  test('host-info query is answered without spawning', () async {
    var factoryCalled = false;
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      hostInfo: () => const SSHHostInfo(
        platform: 'windows', osUser: 'dev', elevated: false,
        inDocker: false, shell: 'powershell',
      ),
      processFactory: (argv, cwd, env) async {
        factoryCalled = true;
        return _EchoProcess(argv)..start();
      },
    );
    final session = await client.execute(
      TpExecCodec.encodeHostInfoQuery(),
    );
    final raw = await utf8.decoder.bind(session.stdout).join();
    final info = SSHHostInfo.fromJson(raw);
    expect(info.platform, 'windows');
    expect(factoryCalled, isFalse);
    client.close();
    await server.close();
  });
}
```

Add `processFactory`/`hostInfo` parameters to `startDualPair` and a `const SSHHostInfo(...)` constructor + `fromJson`/`toJson` (the wire format for the host-info answer: `{"platform":…,"osUser":…,"elevated":…,"inDocker":…,"shell":…}`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client/packages/tp_sshd && dart test test/server_exec_test.dart`
Expected: FAIL — codec and exec handling don't exist.

- [ ] **Step 3: Implement codec + session exec**

`server_process.dart`: `SSHServerProcess`, `SSHProcessFactory`, `SSHHostInfo` (with `toJson`/`fromJson`), `SSHExecRequest`, `TpExecCodec` (encode → `tp1:` + JSON `{"argv":[...],"cwd":...,"env":{...}}`; `tryDecode` returns null for missing prefix or malformed JSON; `isHostInfoQuery` matches `tp1:{"query":"host-info"}`; `encodeHostInfoQuery` produces it).

`server_session.dart`: `void handleSessionRequest(SSHServerChannel channel, SSH_Message_Channel_Request request)` — on `'exec'`: decode; host-info → write JSON to stdout, exit 0; otherwise require `processFactory`, spawn, pipe stdout→`channel.write`, stderr→`channel.writeExtended`, `channel.input`→`process.stdin`, on `exitCode` → send `SSH_Message_Channel_Request('exit-status')` then EOF+close. Non-`tp1:` → reply failure (when `wantReply`) and close the channel.

Run: `cd client/packages/tp_sshd && dart test`
Expected: PASS.

- [ ] **Step 4: Analyze and commit**

```bash
cd client/packages/tp_sshd && dart analyze
cd /c/Users/haung/git/teampilot
git add client/packages/tp_sshd
git commit -m "feat(tp_sshd): structured exec with process factory and host-info query"
```

---

### Task 7: tp_sshd — session shell, pty-req, window-change, signal

**Files:**
- Modify: `client/packages/tp_sshd/lib/src/server_process.dart` (add pty abstraction)
- Modify: `client/packages/tp_sshd/lib/src/server_session.dart` (shell/pty requests)
- Modify: `client/packages/tp_sshd/lib/src/ssh_server.dart` (config: `ptyFactory`)
- Test: `client/packages/tp_sshd/test/server_shell_test.dart`

**Interfaces:**
- Consumes: Task 6 session plumbing.
- Produces:

```dart
class SSHPtyDimensions {
  final int columns, rows, pixelWidth, pixelHeight;
  final Map<String, String> environment; // TERM etc.
}

abstract class SSHServerPty extends SSHServerProcess {
  void resize(int columns, int rows);
  void signal(String name); // 'INT', 'TERM', … per RFC 4254 §6.9
}

typedef SSHPtyFactory =
    Future<SSHServerPty?> Function(SSHPtyDimensions initial);
```

- [ ] **Step 1: Write the failing tests**

```dart
// test/server_shell_test.dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';

class _FakePty implements SSHServerPty {
  final _stdout = StreamController<Uint8List>.broadcast();
  final _stdin = StreamController<List<int>>();
  final resized = <String>[];
  final signaled = <String>[];

  @override
  void resize(int columns, int rows) => resized.add('$columns x $rows');

  @override
  void signal(String name) => signaled.add(name);

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => const Stream.empty();

  @override
  StreamSink<List<int>> get stdin => _stdin.sink;

  @override
  Future<int> get exitCode => Completer<int>().future;

  @override
  void kill() {}
}

void main() {
  test('shell request with pty spawns pty, echoes, resizes, signals', () async {
    final pty = _FakePty();
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      ptyFactory: (initial) async {
        expect(initial.columns, 120);
        expect(initial.environment['TERM'], 'xterm-256color');
        return pty;
      },
    );
    final session = await client.shell(
      pty: SSHPtyType(columns: 120, rows: 40),
    );
    session.done; // stream plumbing

    pty._stdout.add(Uint8List.fromList(utf8.encode('hello')));
    expect(
      utf8.decoder.bind(session.stdout).first,
      completion('hello'),
    );

    session.resizeTerminal(200, 50);
    await pumpEventQueue();
    expect(pty.resized, contains('200 x 50'));

    session.signal(SSHSignal.interrupt);
    await pumpEventQueue();
    expect(pty.signaled, contains('INT'));

    client.close();
    await server.close();
  });

  test('shell without ptyFactory fails the request', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
    );
    await expectLater(
      client.shell(pty: SSHPtyType(columns: 80, rows: 24)),
      throwsA(anything),
    );
    client.close();
    await server.close();
  });
}
```

(Match dartssh2's real `SSHClient.shell`, `SSHPtyType`, `SSHSession.resizeTerminal`, `SSHSession.signal`, `SSHSignal` APIs — the app already exercises them via `SshPtyTransport`.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client/packages/tp_sshd && dart test test/server_shell_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Session request handling adds: `'pty-req'` → stash dimensions + terminal env (no reply beyond channel success when `wantReply`); `'shell'` → require a stashed pty-req then `ptyFactory`; pipe like exec but no exit-status until the pty exits; `'window-change'` → `pty.resize`; `'signal'` → `pty.signal` (map dartssh2's `SSHSignal` enum to RFC names: `interrupt`→`INT`, `terminate`→`TERM`, `kill`→`KILL`, `hangup`→`HUP` — mirror `ssh_client.dart`'s own signal mapping); `'env'` → accumulate into the pty environment.

Run: `cd client/packages/tp_sshd && dart test`
Expected: PASS.

- [ ] **Step 4: Analyze and commit**

```bash
cd client/packages/tp_sshd && dart analyze
cd /c/Users/haung/git/teampilot
git add client/packages/tp_sshd
git commit -m "feat(tp_sshd): interactive shell with pty, resize, and signals"
```

---

### Task 8: tp_sshd — SFTPv3 subsystem server

**Files:**
- Create: `client/packages/tp_sshd/lib/src/sftp_filesystem.dart`
- Create: `client/packages/tp_sshd/lib/src/server_sftp.dart`
- Modify: `client/packages/tp_sshd/lib/src/ssh_server.dart` (config: `sftpFileSystem`)
- Test: `client/packages/tp_sshd/test/server_sftp_test.dart`

**Interfaces:**
- Consumes: `Sftp*Packet` classes + `SftpName`, `SftpFileAttrs`, `SftpStatus`, `SftpFileOpenMode` from `package:dartssh2/protocol.dart` (add these sftp exports to `protocol.dart` and to the fork commit if not already exported — `export 'src/sftp/sftp_packet.dart'; export 'src/sftp/sftp_file_attrs.dart'; export 'src/sftp/sftp_name.dart'; export 'src/sftp/sftp_file_open_mode.dart';`).
- Produces:

```dart
/// Injected filesystem the SFTP subsystem runs on. The app implements this
/// over LocalFilesystem; tests over an in-memory tree.
abstract class SftpFileSystem {
  Future<SftpFileAttrs> stat(String path);
  Future<SftpDirListing> openDir(String path);
  Future<SftpHandle> openFile(String path, SftpFileOpenMode mode, SftpFileAttrs? attrs);
  Future<void> mkdir(String path, SftpFileAttrs attrs);
  Future<void> rmdir(String path);
  Future<void> unlink(String path);
  Future<void> rename(String from, String to);
  Future<String> realpath(String path);
}

/// Opaque per-open handle. `read`/`write` take the offset; SFTPv3 is
/// stateless-offset with a handle for lifetime bookkeeping.
abstract class SftpHandle {
  Future<Uint8List> read(int offset, int length);
  Future<void> write(int offset, Uint8List data);
  Future<void> close();
}

abstract class SftpDirListing {
  Future<List<SftpName>> read();
  Future<void> close();
}
```

- [ ] **Step 1: Write the failing tests**

```dart
// test/server_sftp_test.dart
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';
import 'memory_sftp_filesystem.dart'; // in-memory SftpFileSystem impl (test helper)

void main() {
  late MemorySftpFileSystem fs;

  setUp(() => fs = MemorySftpFileSystem());

  Future<(SSHClient, SSHServer)> connect() => startDualPair(
        hostKeyPair: testHostKey,
        authenticate: (_) async => true,
        clientIdentities: [testDeviceKey],
        sftpFileSystem: fs,
      );

  test('mkdir / write / read / stat / list round trip', () async {
    final (client, server) = await connect();
    final sftp = await client.sftp();
    await sftp.mkdir('/demo');
    final file = await sftp.open('/demo/hello.txt', mode: SftpFileOpenMode.write | SftpFileOpenMode.creat);
    await file.writeBytes(Uint8List.fromList('hello tp_sshd'.codeUnits));
    await file.close();

    final attrs = await sftp.stat('/demo/hello.txt');
    expect(attrs.size, 13);

    final readBack = await sftp.readFile('/demo/hello.txt');
    expect(String.fromCharCodes(readBack), 'hello tp_sshd');

    final names = await sftp.listdir('/demo');
    expect(names.map((n) => n.filename), contains('hello.txt'));
    client.close();
    await server.close();
  });

  test('rename, remove, rmdir', () async {
    final (client, server) = await connect();
    final sftp = await client.sftp();
    await sftp.mkdir('/a');
    final f = await sftp.open('/a/x', mode: SftpFileOpenMode.write | SftpFileOpenMode.creat);
    await f.writeBytes(Uint8List.fromList([1, 2, 3]));
    await f.close();
    await sftp.rename('/a/x', '/a/y');
    await sftp.remove('/a/y');
    await sftp.rmdir('/a');
    await expectLater(sftp.stat('/a/y'), throwsA(anything));
    client.close();
    await server.close();
  });

  test('missing file returns SSH_FX_NO_SUCH_FILE status, not a crash', () async {
    final (client, server) = await connect();
    final sftp = await client.sftp();
    await expectLater(sftp.stat('/nope'), throwsA(isA<SftpStatusError>()));
    client.close();
    await server.close();
  });
}
```

`memory_sftp_filesystem.dart`: a tree of `Map<String, ({bool dir, Uint8List? bytes, SftpFileAttrs attrs})>` implementing `SftpFileSystem`; ~80 lines, straightforward.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client/packages/tp_sshd && dart test test/server_sftp_test.dart`
Expected: FAIL — no subsystem.

- [ ] **Step 3: Implement the subsystem**

`server_sftp.dart`: on session channel request `'subsystem'` with name `'sftp'`: decode each incoming packet (4-byte length + 1-byte type + payload — use `SftpPacket` framing helpers from `src/sftp/sftp_packet.dart`), dispatch by type:

| Type | Request class | Reply |
|---|---|---|
| 1 | `SftpInitPacket` | `SftpVersionPacket(version: 3)` |
| 3 | `SftpOpenPacket` | `SftpHandlePacket` / `SftpStatusPacket` |
| 4 | `SftpClosePacket` | `SftpStatusPacket` OK |
| 5 | `SftpReadPacket` | `SftpDataPacket` / EOF status |
| 6 | `SftpWritePacket` | `SftpStatusPacket` OK |
| 7/8 | `SftpLStatPacket`/`SftpSetStatPacket` | `SftpAttrsPacket` / OK |
| 9/10 | `SftpFStatPacket`/`SftpFSetStatPacket` | attrs on the handle |
| 11 | `SftpOpenDirPacket` | `SftpHandlePacket` |
| 12 | `SftpReadDirPacket` | `SftpNamePacket` / EOF status |
| 13 | `SftpRemovePacket` | OK / NO_SUCH_FILE |
| 14 | `SftpMkdirPacket` | OK |
| 15 | `SftpRmdirPacket` | OK |
| 16 | `SftpRealpathPacket` | `SftpNamePacket` |
| 17 | `SftpStatPacket` | `SftpAttrsPacket` |
| 18 | `SftpRenamePacket` | OK |
| 19/20 | `SftpReadlinkPacket`/`SftpSymlinkPacket` | name / OK |

Every reply carries the request id. Unknown/extended types → `SftpStatusPacket` with `SSH_FX_OP_UNSUPPORTED`. Filesystem errors map to status codes: not-found → 2 (`SSH_FX_NO_SUCH_FILE`), permission → 3, exists → 11, otherwise 4 (failure). All operations route through the injected `SftpFileSystem`.

Run: `cd client/packages/tp_sshd && dart test`
Expected: PASS.

- [ ] **Step 4: Analyze and commit**

```bash
cd client/packages/tp_sshd && dart analyze
cd /c/Users/haung/git/teampilot
git add client/packages/tp_sshd
git commit -m "feat(tp_sshd): SFTPv3 subsystem over injected filesystem"
```

---

### Task 9: tp_sshd — tcpip-forward and forwarded-tcpip channels

**Files:**
- Create: `client/packages/tp_sshd/lib/src/server_forward.dart`
- Modify: `client/packages/tp_sshd/lib/src/ssh_server.dart` (config: `bindServerSocket`)
- Test: `client/packages/tp_sshd/test/server_forward_test.dart`

**Interfaces:**
- Consumes: Task 5 channel layer (locally-opened channels get a `SSH_Message_Channel_Confirmation` path — extend the channel table to allow server-initiated opens).
- Produces:

```dart
/// Injection seam for loopback binds; the app passes `ServerSocket.bind`.
/// Tests pass a fake to assert loopback-only enforcement without sockets.
typedef SSHBindServerSocket =
    Future<ServerSocketHandle> Function(InternetAddress address, int port);

abstract class ServerSocketHandle {
  Stream<ForwardConnection> get connections;
  Future<void> close();
}

/// One accepted TCP connection: bytes ride a forwarded-tcpip channel.
abstract class ForwardConnection {
  Stream<Uint8List> get input;
  StreamSink<List<int>> get output;
  Future<void> get done;
}
```

Config: `SSHBindServerSocket? bindServerSocket` — null → forwarding disabled (every `tcpip-forward` gets `SSH_Message_Request_Failure`).

- [ ] **Step 1: Write the failing tests**

```dart
// test/server_forward_test.dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';

void main() {
  test('forwardRemote binds loopback and pumps bytes', () async {
    // Real loopback sockets — this is the one place unit tests touch the
    // network stack, mirroring the fork's own test philosophy.
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      bindServerSocket: (address, port) =>
          ServerSocket.bind(address, port).then(_RealServerSocketHandle.new),
    );
    final forward = await client.forwardRemote(host: '127.0.0.1', port: 0);
    expect(forward.address, InternetAddress.loopbackIPv4.address);

    // Something on the server host connects to the bound loopback port;
    // bytes must arrive on the phone side over the channel.
    final receivedOnClient = Completer<String>();
    forward.channels.listen((channel) {
      utf8.decoder.bind(channel.stream).listen((data) {
        if (!receivedOnClient.isCompleted) receivedOnClient.complete(data);
      });
    });
    final probe = await Socket.connect('127.0.0.1', forward.port);
    probe.add(Uint8List.fromList('ping'.codeUnits));
    await probe.flush();

    expect(receivedOnClient.future, completion('ping'));
    await probe.close();
    await forward.cancel();
    client.close();
    await server.close();
  });

  test('non-loopback bind requests are refused', () async {
    // tcpip-forward with a non-loopback address must fail even though the
    // injected binder is permissive.
  });

  test('cancel-tcpip-forward releases the bind', () async {
    // bind, cancel, expect the loopback port to refuse connections
  });
}
```

(Complete the two outlined tests with the same harness pattern as the first: `client.forwardRemote`, dial, assert. `_RealServerSocketHandle` adapts `ServerSocket` to `ServerSocketHandle`.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client/packages/tp_sshd && dart test test/server_forward_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

`server_forward.dart`:
- `tcpip-forward` global request → if the requested address is not loopback (`127.0.0.1`, `::1`, `localhost`), reply failure. Else bind via the seam (port 0 → ephemeral), remember `port → bind`, reply `SSH_Message_Request_Success` carrying the assigned port (uint32 payload — see how `ssh_client.dart:480` reads it: `port != 0 ? port : reader.readUint32()`).
- On an accepted connection: open a `forwarded-tcpip` channel (`SSH_Message_Channel_Open('forwarded-tcpip')` with `connectedAddress/Port` and `originatorAddress/Port` per RFC 4254 §7.2), await confirmation, pump connection→channel and channel→connection until either closes.
- `cancel-tcpip-forward` → close and forget the bind, reply success.
- Connection close → unbind everything that connection bound.

Run: `cd client/packages/tp_sshd && dart test`
Expected: PASS.

- [ ] **Step 4: Analyze and commit**

```bash
cd client/packages/tp_sshd && dart analyze
cd /c/Users/haung/git/teampilot
git add client/packages/tp_sshd
git commit -m "feat(tp_sshd): loopback-only remote port forwarding"
```

---

### Task 10: Hardening sweep, README, submodule pointer, full suites

**Files:**
- Create: `client/packages/tp_sshd/README.md`
- Test: `client/packages/tp_sshd/test/server_hardening_test.dart`
- Modify: parent repo submodule pointer

**Interfaces:**
- Consumes: everything above.
- Produces: the finished package; parent repo records the dartssh2 submodule bump.

- [ ] **Step 1: Write the hardening tests**

```dart
// test/server_hardening_test.dart
@TestOn('vm')
library;

void main() {
  test('six failed auth attempts disconnect the client', () async {
    // client with a wrong key, authenticate: false — count failures until
    // the transport closes; assert it is <= 6 and the connection died.
  });

  test('one crashing connection does not kill the listener', () async {
    // start server; connect raw SSHTransport, send garbage after version
    // banner (not even kex) — server must close that socket; then
    // startDualPair still succeeds on a fresh connection.
  });

  test('five concurrent connections all authenticate and exec', () async {
    // five startDualPair rounds in parallel (sequential socket pairs),
    // each running the Task 6 echo exec; all must pass.
  });

  test('rekey mid-session keeps the channel alive', () async {
    // startDualPair + exec echo process that stays open; force
    // client-side rekey (dartssh2 rekeys on transport-level demand or
    // bytes threshold — trigger via the public rekey API if present,
    // otherwise skip-with-reason and cover rekey in the fork tests).
  });
}
```

(Complete each test with the harness patterns from Tasks 3–6.)

- [ ] **Step 2: Run, implement what the failures reveal, commit**

Run: `cd client/packages/tp_sshd && dart test test/server_hardening_test.dart`
Expected: PASS after fixes (throttle count, error isolation around per-connection `onMessage` — wrap handlers in try/catch that disconnects only the offending connection).

```bash
cd client/packages/tp_sshd && dart analyze && dart test
cd /c/Users/haung/git/teampilot
git add client/packages/tp_sshd
git commit -m "test(tp_sshd): auth throttle, crash isolation, concurrency, rekey"
```

- [ ] **Step 3: Write the README**

```markdown
# tp_sshd

Pure-Dart SSH server for TeamPilot's embedded desktop server. Built on the
dartssh2 protocol primitives (../dartssh2 `protocol.dart`).

## Surface
- Auth: publickey (ssh-ed25519 device keys), fail-closed, 6-attempt throttle.
- Channels: session (structured `tp1:` exec + interactive shell/pty),
  sftp subsystem (SFTPv3, injected filesystem), tcpip-forward (loopback only).
- KEX: curve25519-sha256, ed25519 host keys, chacha20-poly1305 / aes256-gcm,
  strict KEX (RFC 9142).

## Usage
```dart
final server = await SSHServer.bind(
  connectionIterator,
  config: SSHServerConfig(hostKeyPair: hostKey, authenticate: ...),
);
```
Everything is injected: process factory, pty factory, filesystem, bind seam.
See test/dual_test_utils.dart for a complete wiring example.
```

- [ ] **Step 4: Push the submodule and bump the parent pointer**

```bash
cd client/packages/dartssh2
git push origin main
cd /c/Users/haung/git/teampilot
git add client/packages/dartssh2
git commit -m "chore: bump dartssh2 submodule — protocol export + server-role kex"
```

- [ ] **Step 5: Full verification per repo rules**

```bash
cd client/packages/dartssh2 && dart analyze && dart test
cd ../tp_sshd && dart analyze && dart test
cd ../../.. && cd client && dart run tool/run_tests.dart
```

Expected: all green. The app suite must be unaffected (no app code changed in this plan).

---

## Self-Review Notes

- Spec coverage: transport/KEX/auth (Tasks 2–4), session/exec/pty (6–7), SFTP (8), forwarding (9), algorithm surface + strict kex (Task 3 constraint + Task 2), throttling/revocation-friendly auth (4, 10), loopback-only binds (9), dual tests everywhere. App-layer items (EmbeddedSshServer, offer v2, RemoteCommandCodec, PairedDeviceStore.issueDevice, l10n) are deliberately out of this plan — they form the follow-up app-integration plan per the scope split.
- The spec's "revocation tears down established channels" is app-layer orchestration (the app's authenticator consults the store; teardown on revoke needs an app-level channel registry view) — noted for the follow-up plan; tp_sshd exposes `SSHServer` connection handles sufficient for it via `activeConnections` plus a per-connection close (add `closeConnection(username, publicKey)` in the app plan if the surface above proves insufficient).
- Test PEMs and enum/method names flagged inline where the implementer must verify against the real fork code before running.
