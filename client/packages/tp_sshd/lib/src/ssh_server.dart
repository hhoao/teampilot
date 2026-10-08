import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHKeyPair, SSHSocket;
import 'package:dartssh2/protocol.dart';

import 'server_connection.dart';
import 'server_forward.dart';
import 'server_process.dart';
import 'sftp_filesystem.dart';

/// The narrow negotiation surface advertised by tp_sshd servers (spec:
/// x25519 KEX, ed25519 host keys, AEAD ciphers).
///
/// Key exchange is deliberately ECDH-only: a client that cannot speak
/// x25519 fails the exchange by design, and the list must not be broadened
/// with DH-family algorithms.
const SSHAlgorithms tpServerAlgorithms = SSHAlgorithms(
  kex: [SSHKexType.x25519Rfc, SSHKexType.x25519],
  hostkey: [SSHHostkeyType.ed25519],
  cipher: [SSHCipherType.chacha20poly1305, SSHCipherType.aes256gcm],
  mac: [SSHMacType.hmacSha256],
);

/// Configuration for an [SSHServer].
class SSHServerConfig {
  SSHServerConfig({
    required this.hostKeyPair,
    required this.expectedUsername,
    required this.authenticate,
    this.authTimeout = const Duration(seconds: 30),
    this.authFailureMinDelay = const Duration(milliseconds: 10),
    this.rekeyBytes = 1024 * 1024 * 1024,
    this.rekeyInterval = const Duration(hours: 1),
    this.maxAuthAttempts = 6,
    this.maxChannels = 10,
    this.processFactory,
    this.shellExecFactory,
    this.ptyFactory,
    this.hostInfo,
    this.sftpFileSystem,
    this.forwarding,
    this.onAuthenticated,
    this.printDebug,
    this.printTrace,
  });

  /// The host key the server signs its key exchanges with. Must be an
  /// ed25519 key: it is the only host key algorithm [tpServerAlgorithms]
  /// advertises.
  final SSHKeyPair hostKeyPair;

  /// The only username this server authenticates: the user the connection
  /// was offered to. A request for any other user counts as a failed
  /// authentication attempt.
  final String expectedUsername;

  /// Decides whether an authentication attempt is accepted. Called once per
  /// `publickey` userauth request — both for public-key probing requests
  /// (the answer decides the `USERAUTH_PK_Ok` reply) and for signed ones
  /// (where the signature has already been verified when this is called).
  final Future<bool> Function(SSHServerAuthRequest request) authenticate;

  /// How long a connection may live without completing authentication
  /// before the server closes it.
  final Duration authTimeout;

  /// The minimum wall-clock time from the receipt of a `USERAUTH_REQUEST` to
  /// its failure reply (the `USERAUTH_FAILURE`, or the throttle disconnect
  /// past [maxAuthAttempts]).
  ///
  /// This is sshd's anti-oracle floor (auth2.c: `ensure_minimum_time_since`,
  /// MIN_FAIL_DELAY_SECONDS): without it, the failure paths have disjoint
  /// costs — a wrong key pays the full signature verify plus the embedder's
  /// authenticate callback, an unknown user fails at the username compare —
  /// so a timing peer learns whether a username matched. Padding every
  /// failed attempt out to one floor makes the classes indistinguishable.
  /// The default (10 ms) comfortably dominates every failure path's real
  /// cost; `Duration.zero` disables the padding. sshd additionally jitters
  /// the delay per username (`user_specific_delay`); that is a hardening
  /// follow-up, not part of the floor.
  final Duration authFailureMinDelay;

  /// How many outbound bytes a session may carry before the server initiates
  /// a key exchange of its own, or `null` to disable the byte trigger.
  ///
  /// Defaults to 1 GiB. This is a deliberate divergence from OpenSSH, whose
  /// 10.2 default is **no configured `RekeyLimit` at all** — `RekeyLimit
  /// default none` (sshd_config.5:1788-1812; servconf.c:398-401 defaults
  /// `rekey_limit = 0`, `rekey_interval = 0`): the only bound firing by
  /// default is cipher geometry (`max_blocks = 2^(block×2)` blocks ≈ 64 GiB
  /// for AES's 16-byte blocks, plus a 2^31-packet hard cap), which
  /// essentially never trips for a normal session (audit row B06). tp_sshd's
  /// deployment is the opposite of an internet-facing sshd's: pairing
  /// sessions are long-lived and frequently low-volume, so a
  /// geometry-scale byte-only bound would never fire and the session would
  /// keep its keys forever — exactly the B06 finding. Pairing
  /// [rekeyInterval]'s 1 h with a 1 GiB byte bound guarantees every live
  /// pairing session rotates keys at least hourly; `null` restores
  /// sshd-default-equivalent behavior for embedders who want it.
  final int? rekeyBytes;

  /// How long an authenticated session may live before the server initiates
  /// a key exchange of its own, or `null` to disable the interval trigger.
  ///
  /// Defaults to 1 h. OpenSSH only rekeys on time when `RekeyLimit`
  /// configures an interval (serverloop.c:171, packet.c:1095-1097 — the 10.2
  /// default configures none, audit row B07); the default here exists for
  /// the same pairing-session rationale as [rekeyBytes]: an idle-but-alive
  /// session is exactly the case a byte counter never reaches.
  final Duration? rekeyInterval;

  /// How many authentication attempts a connection may make before the
  /// server disconnects it.
  final int maxAuthAttempts;

  /// How many channels may be open on one connection at the same time
  /// (OpenSSH's default is 10 per session). A CHANNEL_OPEN beyond the cap is
  /// refused with reason 4, `resource shortage`, instead of confirmed.
  final int maxChannels;

  /// Spawns the process backing a structured `exec` request (see
  /// [TpExecCodec]). Receives the decoded argv, working directory and
  /// environment; a `null` return — or an unconfigured factory — refuses the
  /// request. The server itself never builds a command line.
  final SSHProcessFactory? processFactory;

  /// Spawns the process backing a plain command-string `exec` request (no
  /// `tp1:` prefix): a raw shell line, run by the host's native shell (see
  /// [SSHShellExecFactory]). A `null` return — or an unconfigured factory —
  /// refuses the request. When configured, this is how a client that sends
  /// bare `"command -v claude"`-style strings (legacy exec callers) is served;
  /// structured `tp1:` requests still take [processFactory].
  final SSHShellExecFactory? shellExecFactory;

  /// Spawns the pseudo-terminal backing a `shell` request. The request is
  /// only served on a channel that stashed a `pty-req` first; a `null`
  /// return — or an unconfigured factory — refuses the request.
  final SSHPtyFactory? ptyFactory;

  /// Supplies the host snapshot answered for the `tp1:` host-info query.
  /// `null` refuses the query; it is never answered by spawning a process.
  final SSHHostInfo Function()? hostInfo;

  /// The filesystem the `sftp` subsystem serves. A `subsystem` request for
  /// `sftp` is only served when this is configured; without it the request
  /// is refused.
  final SftpFileSystem? sftpFileSystem;

  /// The forwarding surface: remote (`tcpip-forward`) and direct
  /// (`direct-tcpip`) TCP forwarding, governed by one [SSHForwardingConfig].
  /// `null` disables forwarding outright — every `tcpip-forward` and
  /// `direct-tcpip` request is refused.
  final SSHForwardingConfig? forwarding;

  /// Invoked exactly once per connection, after the signed publickey request
  /// verifies and `authenticate` accepts — the embedder's point to record
  /// which connection belongs to which device (revocation teardown).
  final void Function(SSHServerConnection connection, SSHServerAuthRequest request)?
      onAuthenticated;

  /// Function invoked with debug logging, mirroring [SSHSocket] transports.
  final void Function(String? message)? printDebug;

  /// Function invoked with trace logging, mirroring [SSHSocket] transports.
  final void Function(String? message)? printTrace;
}

/// The forwarding direction mask, mirroring `sshd_config`'s
/// AllowTcpForwarding (`servconf.c`: `yes|all|no|local|remote`). It is a
/// direction bitmask, not a boolean: `direct-tcpip` needs the local bit,
/// `tcpip-forward` the remote bit.
enum SshTcpForwardingMode {
  /// AllowTcpForwarding `no`: neither direction.
  deny,

  /// `direct-tcpip` allowed, `tcpip-forward` refused.
  local,

  /// `tcpip-forward` allowed, `direct-tcpip` refused.
  remote,

  /// AllowTcpForwarding `yes`/`all`: both directions.
  both;

  /// Whether `direct-tcpip` (the local, outbound-dial direction) is on.
  bool get allowsLocal =>
      this == SshTcpForwardingMode.local ||
      this == SshTcpForwardingMode.both;

  /// Whether `tcpip-forward` (the remote, inbound-bind direction) is on.
  bool get allowsRemote =>
      this == SshTcpForwardingMode.remote ||
      this == SshTcpForwardingMode.both;
}

/// AllowTcpForwarding + PermitOpen + the bind/dial seams in one surface
/// (the direct-tcpip forwarding design §1). A `null`
/// [SSHServerConfig.forwarding] is the hard disable — the equivalent of
/// `sshd -d`: both forwarding directions are refused outright.
final class SSHForwardingConfig {
  SSHForwardingConfig({
    required this.allowTcpForwarding,
    required this.dialSocket,
    required this.bindServerSocket,
    this.permitOpen,
    this.dialTimeout = const Duration(seconds: 30),
  });

  /// The direction mask governing both forwarding kinds: `direct-tcpip`
  /// reads [SshTcpForwardingMode.allowsLocal], `tcpip-forward` reads
  /// [SshTcpForwardingMode.allowsRemote].
  final SshTcpForwardingMode allowTcpForwarding;

  /// The per-connection target predicate, the PermitOpen equivalent: a
  /// `direct-tcpip` open is checked against the dialed target `(host, port)`
  /// and a `tcpip-forward` request against the bind address `(host, port)`,
  /// each before any seam is consulted. Receives the connection, so the
  /// embedder can decide per device (it recorded which connection belongs to
  /// which device in [SSHServerConfig.onAuthenticated]). `null` allows every
  /// target, like OpenSSH's default `PermitOpen any`.
  final Future<bool> Function(
          SSHServerConnection connection, String host, int port)?
      permitOpen;

  /// The dial seam for `direct-tcpip`: receives the host string and port the
  /// client asked for and returns a connected [ForwardConnection] — the seam
  /// resolves the host and connects, like OpenSSH's server-side getaddrinfo
  /// + connect. A throw — or a [dialTimeout] expiry — refuses just that
  /// channel with reason 2, `connect failed`; the SSH connection survives.
  final SSHDialSocket dialSocket;

  /// The bind seam for remote port forwarding (`tcpip-forward`, RFC 4254
  /// §7). The app passes a `ServerSocket.bind` adapter; tests pass fakes (or
  /// a recording wrapper) to observe or refuse binds without sockets. Only
  /// loopback addresses are ever bound, and a non-loopback request is
  /// refused before this seam is consulted.
  final SSHBindServerSocket bindServerSocket;

  /// The guard width that bounds only the dial itself, so a stuck dial can
  /// never leave a channel-open pending forever (prevents a hung pending
  /// open). `future.timeout(dialTimeout)` bounds the dial; on expiry the
  /// channel is refused like any dial failure. The confirmation round-trip is
  /// synchronous and not covered by this budget.
  final Duration dialTimeout;
}

/// A client's authentication request, as handed to
/// [SSHServerConfig.authenticate].
class SSHServerAuthRequest {
  const SSHServerAuthRequest({
    required this.username,
    required this.algorithm,
    required this.publicKey,
  });

  /// The username the client is authenticating as.
  final String username;

  /// The public key algorithm of the offered key — always `'ssh-ed25519'`,
  /// the only one the server advertises.
  final String algorithm;

  /// The offered public key as an OpenSSH wire blob.
  final Uint8List publicKey;
}

/// An SSH server driving accepted sockets through the TeamPilot protocol
/// surface.
///
/// The server does not own listening: [bind] consumes already-accepted
/// sockets from a [StreamIterator], so the embedder decides whether they come
/// from a real [ServerSocket](dart:io), a WebSocket bridge, or an in-memory
/// test pair.
class SSHServer {
  SSHServer._(this._config);

  final SSHServerConfig _config;

  /// Live connections, in acceptance order.
  final _connections = <SSHServerConnection>{};

  final _done = Completer<void>();

  /// The iterator [bind] is draining; kept so [close] can stop the loop.
  StreamIterator<SSHSocket>? _connectionsIterator;

  /// The running accept loop, if any.
  Future<void>? _acceptLoop;

  var _isClosed = false;

  /// Starts serving [connections].
  ///
  /// Each accepted socket gets its own [SSHServerConnection] running the
  /// server-side transport with [tpServerAlgorithms] and the configured host
  /// key. The returned server keeps accepting until [close] is called or the
  /// stream ends.
  static Future<SSHServer> bind(
    StreamIterator<SSHSocket> connections, {
    required SSHServerConfig config,
  }) async {
    final server = SSHServer._(config);
    server._connectionsIterator = connections;
    server._acceptLoop = server._acceptConnections(connections);
    return server;
  }

  /// Number of connections the server is currently serving.
  int get activeConnections => _connections.length;

  /// Completes when the server stops accepting.
  ///
  /// Normally that is [close] or the connection stream ending; if the stream
  /// itself errors, this completes with that error instead — after every live
  /// connection has been torn down. (The error is marked handled when it is
  /// raised, so a caller that never awaits [done] cannot turn a contained
  /// stream failure into an unhandled zone error; awaiting still sees it.)
  Future<void> get done => _done.future;

  Future<void> _acceptConnections(StreamIterator<SSHSocket> connections) async {
    try {
      while (await connections.moveNext()) {
        if (_isClosed) break;
        _spawnConnection(connections.current);
      }
      _done.complete();
    } on Object catch (error, stackTrace) {
      // The connection stream itself died (the embedder's accept source
      // broke). That must not surface as an unhandled error in whoever's zone
      // happens to be around, and it must not leave live connections hanging
      // off a dead listener: stop accepting and tear them all down.
      _isClosed = true;
      for (final connection in List.of(_connections)) {
        unawaited(connection.close());
      }
      _done.completeError(error, stackTrace);
      // Nobody has to await [done]; a dropped error would surface as an
      // unhandled zone error, which is exactly what this containment is for.
      _done.future.catchError((_) {});
    }
  }

  void _spawnConnection(SSHSocket socket) {
    final connection = SSHServerConnection(socket, config: _config);
    _connections.add(connection);
    connection.done
        .whenComplete(() => _connections.remove(connection))
        .ignore();
  }

  /// Stops accepting connections and closes every live one.
  ///
  /// The injected connection stream is cancelled (not closed — the embedder
  /// owns it), which also unblocks a pending accept.
  Future<void> close() async {
    final wasClosed = _isClosed;
    _isClosed = true;
    // Cancelling the iterator completes a pending moveNext with false, which
    // ends the accept loop.
    await _connectionsIterator?.cancel();
    await _acceptLoop;
    if (wasClosed) return;
    for (final connection in List.of(_connections)) {
      await connection.close();
    }
  }
}
