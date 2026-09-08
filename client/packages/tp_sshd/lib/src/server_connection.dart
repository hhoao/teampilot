import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHSocket, SSHTransport;
import 'package:dartssh2/protocol.dart';

import 'server_userauth.dart';
import 'ssh_server.dart' show SSHServerAuthRequest, SSHServerConfig, tpServerAlgorithms;

/// Lifecycle phases of an [SSHServerConnection].
enum _Phase {
  /// Handshake done; the client is trying to authenticate. Everything except
  /// the service negotiation and userauth is refused.
  auth,

  /// Authenticated; session traffic (channels) is served. Reached when a
  /// signed `publickey` userauth request both verified and was trusted.
  running,

  /// The connection is gone.
  closed,
}

/// One accepted connection: a server-role [SSHTransport] plus the
/// connection-level state machine, the publickey userauth service, and the
/// auth timeout that bounds the pre-authentication phase.
class SSHServerConnection {
  SSHServerConnection(
    this.socket, {
    required SSHServerConfig config,
  }) : _config = config {
    // SSHTransport takes its handlers as final constructor-injected fields,
    // so the state machine has to be wired in right here.
    _transport = SSHTransport(
      socket,
      isServer: true,
      hostKeyPair: config.hostKeyPair,
      algorithms: tpServerAlgorithms,
      printDebug: config.printDebug,
      printTrace: config.printTrace,
      onMessage: _handleMessage,
    );
    _authTimer = Timer(config.authTimeout, _onAuthTimeout);
    // The transport's done future completes with an error when the transport
    // is terminated by one; the connection only cares about the timing.
    _transport.done.whenComplete(_onTransportClosed).ignore();
  }

  /// The socket this connection serves.
  final SSHSocket socket;

  final SSHServerConfig _config;

  late final SSHTransport _transport;
  late final Timer _authTimer;
  var _phase = _Phase.auth;

  /// Failed authentication attempts so far, for the
  /// [SSHServerConfig.maxAuthAttempts] throttle.
  var _authAttempts = 0;

  /// Completes when the underlying transport closes, normally or with an
  /// error.
  Future<void> get done => _transport.done;

  /// Closes the connection and its socket.
  Future<void> close() async {
    _authTimer.cancel();
    _phase = _Phase.closed;
    await _transport.close();
  }

  /// Auth-phase message handling.
  ///
  /// Returns whether the message was recognized, so the transport answers
  /// unrecognized ones with SSH_MSG_UNIMPLEMENTED (RFC 4253 §11).
  bool _handleMessage(Uint8List payload) {
    switch (_phase) {
      case _Phase.closed:
        return false;
      case _Phase.auth:
        return _handleAuthMessage(payload);
      case _Phase.running:
        // No session traffic is served yet; Task 5 replaces this branch
        // with channel handling.
        return false;
    }
  }

  bool _handleAuthMessage(Uint8List payload) {
    switch (SSHMessage.readMessageId(payload)) {
      case SSH_Message_Service_Request.messageId:
        final message = SSH_Message_Service_Request.decode(payload);
        if (message.serviceName == 'ssh-userauth') {
          _transport.sendPacket(
            SSH_Message_Service_Accept(message.serviceName).encode(),
          );
        } else {
          _disconnect(
            SSHDisconnectReason.serviceNotAvailable,
            'Service not available: ${message.serviceName}',
          );
        }
        return true;
      case SSH_Message_Userauth_Request.messageId:
        // The trust decision is the embedder's async authenticate callback,
        // so the request is handled detached from the synchronous
        // onMessage dispatch.
        unawaited(_handleUserauthRequest(payload));
        return true;
      default:
        // Unrecognized message: let the transport answer with
        // SSH_MSG_UNIMPLEMENTED.
        return false;
    }
  }

  /// Handles one `SSH_Message_Userauth_Request` (RFC 4252).
  ///
  /// Publickey is the only method served, and only for
  /// [SSHServerConfig.expectedUsername]. Probing requests (no signature) are
  /// answered with `USERAUTH_PK_Ok` when [SSHServerConfig.authenticate]
  /// trusts the key; signed requests authenticate only when the RFC 4252 §7
  /// signature verifies AND the key is trusted. Every failure counts toward
  /// [SSHServerConfig.maxAuthAttempts].
  Future<void> _handleUserauthRequest(Uint8List payload) async {
    final SSH_Message_Userauth_Request message;
    try {
      message = SSH_Message_Userauth_Request.decode(payload);
    } on Object {
      _disconnect(
        SSHDisconnectReason.protocolError,
        'Malformed userauth request',
      );
      return;
    }

    if (message.methodName != 'publickey' ||
        message.user != _config.expectedUsername) {
      // Fail closed: no other method is served, and requests for any other
      // user are failed (counted), not answered.
      _failAuthAttempt();
      return;
    }

    final publicKeyAlgorithm = message.publicKeyAlgorithm;
    final publicKey = message.publicKey;
    if (publicKeyAlgorithm == null || publicKey == null) {
      _failAuthAttempt();
      return;
    }

    if (message.signature != null) {
      // A signed request must prove possession of the private key before
      // the embedder is asked whether it trusts the public one.
      if (!verifyEd25519UserauthSignature(
        sessionId: _transport.sessionId!,
        request: message,
      )) {
        _failAuthAttempt();
        return;
      }
    }

    var trusted = false;
    try {
      trusted = await _config.authenticate(
        SSHServerAuthRequest(
          username: message.user,
          algorithm: publicKeyAlgorithm,
          publicKey: publicKey,
        ),
      );
    } on Object {
      // A misbehaving authenticate callback is a failed attempt, not an
      // unhandled error on the connection.
      trusted = false;
    }
    // The connection may have been closed (or torn down by the throttle)
    // while the embedder was deciding.
    if (_phase != _Phase.auth) return;

    if (message.signature == null) {
      // Public-key probing (RFC 4252 §7.8): tell the client the key is worth
      // signing with.
      if (trusted) {
        _transport.sendPacket(
          SSH_Message_Userauth_PK_Ok(
            publicKeyAlgorithm: publicKeyAlgorithm,
            publicKey: publicKey,
          ).encode(),
        );
      } else {
        _failAuthAttempt();
      }
      return;
    }

    if (trusted) {
      // Authenticated: cancel the auth timeout so it cannot tear down a
      // live connection later, then start serving session traffic.
      _authTimer.cancel();
      _phase = _Phase.running;
      _transport.sendPacket(SSH_Message_Userauth_Success().encode());
      return;
    }
    _failAuthAttempt();
  }

  /// Counts and answers one failed authentication attempt.
  ///
  /// After [SSHServerConfig.maxAuthAttempts] failures the connection is
  /// disconnected (RFC 4253 §11.1 reason 14) instead of answered. The
  /// failure never advertises continuable methods: publickey is the only
  /// method there is, and offering it would just invite another attempt.
  void _failAuthAttempt() {
    _authAttempts += 1;
    if (_authAttempts >= _config.maxAuthAttempts) {
      _disconnect(
        SSHDisconnectReason.noMoreAuthMethodsAvailable,
        'Too many failed authentication attempts',
      );
      return;
    }
    _transport.sendPacket(
      SSH_Message_Userauth_Failure(methodsLeft: const []).encode(),
    );
  }

  /// Closes connections that never finished authenticating.
  void _onAuthTimeout() {
    if (_phase != _Phase.auth) return;
    _config.printDebug?.call(
      'tp_sshd: closing connection after auth timeout '
      '(${_config.authTimeout})',
    );
    unawaited(close());
  }

  void _onTransportClosed() {
    _authTimer.cancel();
    _phase = _Phase.closed;
  }

  /// Sends a disconnect message and closes the connection.
  void _disconnect(SSHDisconnectReason reason, String description) {
    _transport.sendPacket(
      SSH_Message_Disconnect(
        reasonCode: reason.code,
        description: description,
      ).encode(),
    );
    unawaited(close());
  }
}
