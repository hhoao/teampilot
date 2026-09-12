import 'dart:async';

import 'package:dartssh2/protocol.dart'
    show SSH_Message_Channel_Open_Failure;

import 'server_forward.dart' show ForwardConnection;
import 'ssh_server.dart' show SSHForwardingConfig;

/// Eventual outcome of a client-opened `direct-tcpip` open.
///
/// [DirectDialRefused] sends a CHANNEL_OPEN_FAILURE; [DirectDialConnected]
/// lets the connection confirm the channel and start the shared pump. A
/// connection that closes while the dial is in flight is the caller's
/// concern (its `_phase` check destroys [DirectDialConnected.connection]).
sealed class DirectDialResult {}

/// The server refuses the open (reason aligned with OpenSSH).
final class DirectDialRefused extends DirectDialResult {
  DirectDialRefused(this.reasonCode, this.description);
  final int reasonCode;
  final String description;
}

/// The dial succeeded; [connection] rides a `direct-tcpip` channel.
final class DirectDialConnected extends DirectDialResult {
  DirectDialConnected(this.connection);
  final ForwardConnection connection;
}

/// Gates and dials one `direct-tcpip` channel open (RFC 4254 §7.1).
///
/// Parallel to [SSHServerForwarder]: gate order mirrors OpenSSH
/// `server_request_direct_tcpip` + `channel_connect_to_port` — disabled /
/// bad port / PermitOpen first (reason 1), then dial; any dial failure is
/// reason 2 (`SSH2_OPEN_CONNECT_FAILED`), never a dropped connection.
class SSHServerDirectDialer {
  SSHServerDirectDialer({
    required SSHForwardingConfig forwarding,
    required Future<bool> Function(String host, int port) allowTarget,
  })  : _forwarding = forwarding,
        _allowTarget = allowTarget;

  final SSHForwardingConfig _forwarding;
  final Future<bool> Function(String host, int port) _allowTarget;

  static const _maxTargetPort = 0xffff;

  /// Runs the gates and the dial. Does not touch the connection.
  Future<DirectDialResult> dial(String host, int port) async {
    if (!_forwarding.allowTcpForwarding.allowsLocal) {
      return DirectDialRefused(
        SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited,
        'TCP forwarding is disabled',
      );
    }
    if (port < 0 || port > _maxTargetPort) {
      return DirectDialRefused(
        SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited,
        'invalid target port $port',
      );
    }
    if (!await _allowTarget(host, port)) {
      return DirectDialRefused(
        SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited,
        'forwarding disabled for $host:$port',
      );
    }

    final ForwardConnection connection;
    try {
      connection = await _forwarding
          .dialSocket(host, port)
          .timeout(_forwarding.dialTimeout);
    } on Object catch (error) {
      return DirectDialRefused(
        SSH_Message_Channel_Open_Failure.codeConnectFailed,
        error.toString(),
      );
    }
    return DirectDialConnected(connection);
  }
}