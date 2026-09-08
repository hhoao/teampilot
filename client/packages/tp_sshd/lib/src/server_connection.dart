import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHSocket, SSHTransport;
import 'package:dartssh2/protocol.dart';

import 'ssh_server.dart' show SSHServerConfig, tpServerAlgorithms;

/// Lifecycle phases of an [SSHServerConnection].
enum _Phase {
  /// Handshake done; the client is trying to authenticate. Everything except
  /// the service negotiation is refused.
  auth,

  /// Authenticated; session traffic (channels) is served. Reached once
  /// userauth lands (Task 4+).
  running,

  /// The connection is gone.
  closed,
}

/// One accepted connection: a server-role [SSHTransport] plus the
/// connection-level state machine and the auth timeout that bounds the
/// pre-authentication phase.
///
/// Task 3 scope: the auth phase accepts the `ssh-userauth` service request
/// and fails every authentication attempt closed (there is no userauth
/// service yet — Task 4 adds one driven by [SSHServerConfig.authenticate]).
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
        // Fail closed. The server has no userauth service yet, so every
        // authentication attempt is answered with a failure carrying no
        // continuable methods — every client then terminates its auth
        // (dartssh2's SSHClient gives up and errors out) instead of waiting
        // for an answer that would never come. Task 4 replaces this with
        // real publickey userauth driven by [SSHServerConfig.authenticate].
        _transport.sendPacket(
          SSH_Message_Userauth_Failure(methodsLeft: const []).encode(),
        );
        return true;
      default:
        // Unrecognized message: let the transport answer with
        // SSH_MSG_UNIMPLEMENTED.
        return false;
    }
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
