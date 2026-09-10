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
    this.maxAuthAttempts = 6,
    this.processFactory,
    this.ptyFactory,
    this.hostInfo,
    this.sftpFileSystem,
    this.bindServerSocket,
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

  /// How many authentication attempts a connection may make before the
  /// server disconnects it.
  final int maxAuthAttempts;

  /// Spawns the process backing a structured `exec` request (see
  /// [TpExecCodec]). Receives the decoded argv, working directory and
  /// environment; a `null` return — or an unconfigured factory — refuses the
  /// request. The server itself never builds a command line.
  final SSHProcessFactory? processFactory;

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

  /// The bind seam for remote port forwarding (`tcpip-forward`, RFC 4254
  /// §7). The app passes a `ServerSocket.bind` adapter; `null` disables
  /// forwarding outright — every `tcpip-forward` request is refused. Only
  /// loopback addresses are ever bound, and a non-loopback request is
  /// refused before this seam is consulted.
  final SSHBindServerSocket? bindServerSocket;

  /// Function invoked with debug logging, mirroring [SSHSocket] transports.
  final void Function(String? message)? printDebug;

  /// Function invoked with trace logging, mirroring [SSHSocket] transports.
  final void Function(String? message)? printTrace;
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

  Future<void> _acceptConnections(StreamIterator<SSHSocket> connections) async {
    while (await connections.moveNext()) {
      if (_isClosed) break;
      _spawnConnection(connections.current);
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
