import 'dart:async';
import 'dart:io';

import '../../utils/logging/logger_utils.dart';

typedef TunnelSocketConnect = Future<WebSocket> Function(Uri url);

/// Phone side of a relay tunnel: exposes a loopback TCP port whose bytes ride
/// a `/dial` WebSocket to the paired desktop.
///
/// The loopback address must never be persisted as an [SshProfile.host]; it
/// only lives for the duration of this tunnel. Each accepted TCP connection
/// gets its own dial so concurrent sessions never interleave bytes.
class PhoneRelayTunnel {
  PhoneRelayTunnel({
    TunnelSocketConnect? connectSocket,
    this.dialTimeout = const Duration(seconds: 15),
  }) : _connectSocket = connectSocket ?? _defaultConnect;

  final Duration dialTimeout;
  final TunnelSocketConnect _connectSocket;

  ServerSocket? _server;
  final Set<WebSocket> _sockets = {};
  final Set<Socket> _clients = {};

  InternetAddress get address => InternetAddress.loopbackIPv4;

  int get port => _server?.port ?? 0;

  bool get isClosed => _server == null;

  Future<void> open({
    required Uri relayUrl,
    required String hostId,
    required String channel,
    String? deviceId,
    String? inviteToken,
    String? relayGrant,
  }) async {
    if (_server != null) {
      throw StateError('Tunnel is already open');
    }
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    _server = server;
    server.listen(
      (client) => unawaited(_bridge(client, _dialUrl(relayUrl, hostId, channel,
          deviceId, inviteToken, relayGrant))),
      onError: (Object _) {},
      cancelOnError: false,
    );
  }

  Uri _dialUrl(
    Uri relayUrl,
    String hostId,
    String channel,
    String? deviceId,
    String? inviteToken,
    String? relayGrant,
  ) {
    return relayUrl.replace(
      scheme: relayUrl.scheme == 'wss' ? 'wss' : 'ws',
      path: '/dial',
      queryParameters: {
        'hostId': hostId,
        'channel': channel,
        if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
        if (inviteToken != null && inviteToken.isNotEmpty)
          'inviteToken': inviteToken,
        if (relayGrant != null && relayGrant.isNotEmpty)
          'relayGrant': relayGrant,
      },
    );
  }

  Future<void> _bridge(Socket client, Uri dialUrl) async {
    WebSocket dial;
    try {
      dial = await _connectSocket(dialUrl).timeout(dialTimeout);
    } on Object catch (error, stackTrace) {
      AppLogger.instance.w(
        '[connect-relay] tunnel dial failed class=${error.runtimeType}',
        stackTrace: stackTrace,
      );
      client.destroy();
      return;
    }
    _sockets.add(dial);
    _clients.add(client);
    dial.listen(
      (data) => client.add(data as List<int>),
      onDone: () => _teardown(dial, client),
      onError: (Object _) => _teardown(dial, client),
      cancelOnError: true,
    );
    client.listen(
      dial.add,
      onDone: () => _teardown(dial, client),
      onError: (Object _) => _teardown(dial, client),
      cancelOnError: true,
    );
  }

  void _teardown(WebSocket dial, Socket client) {
    _sockets.remove(dial);
    _clients.remove(client);
    client.destroy();
    unawaited(dial.close());
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    for (final socket in _sockets.toList(growable: false)) {
      unawaited(socket.close());
    }
    _sockets.clear();
    // Destroying clients first frees the sockets even when their dial
    // WebSocket peer already died mid-handshake.
    for (final client in _clients.toList(growable: false)) {
      client.destroy();
    }
    _clients.clear();
    // Not awaited: server shutdown may outlive this call without blocking
    // callers that are tearing down a session.
    unawaited(server?.close());
  }
}

Future<WebSocket> _defaultConnect(Uri url) => WebSocket.connect(url.toString());
