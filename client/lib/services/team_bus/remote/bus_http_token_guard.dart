import 'dart:async';
import 'dart:io';

import '../mcp/teammate_bus_mcp_config.dart';

/// A loopback TCP proxy that guards the in-process HTTP bus for **remote cursor**
/// members (P3b #3). cursor speaks plain HTTP MCP over the reverse tunnel; this
/// guard sits in front of the bus HTTP port and admits a connection only when
/// its first request carries a matching `X-Bus-Token` header, then transparently
/// pipes to the real bus port.
///
/// Local members are unaffected — they connect to the bus HTTP server directly
/// and never traverse this guard. Per connection the token is checked once (on
/// the first request); keep-alive follow-ups on the same authenticated
/// connection are piped through.
class BusHttpTokenGuard {
  BusHttpTokenGuard({required this.token, required this.upstreamPort});

  /// Expected `X-Bus-Token` value (the per-session mount token).
  final String token;

  /// The real bus HTTP port ([TeammateBusMcpServer.port]) connections proxy to.
  final int upstreamPort;

  ServerSocket? _server;
  final _conns = <Socket>[];

  int get port => _server!.port;

  Future<int> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_onConnection);
    return server.port;
  }

  void _onConnection(Socket socket) {
    _conns.add(socket);
    _Handshaker(
      socket: socket,
      token: token,
      upstreamPort: upstreamPort,
      onDone: () => _conns.remove(socket),
    ).start();
  }

  Future<void> close() async {
    for (final c in _conns.toList()) {
      c.destroy();
    }
    _conns.clear();
    await _server?.close();
    _server = null;
  }
}

class _Handshaker {
  _Handshaker({
    required this.socket,
    required this.token,
    required this.upstreamPort,
    required this.onDone,
  });

  final Socket socket;
  final String token;
  final int upstreamPort;
  final void Function() onDone;

  final _buf = <int>[];
  Socket? _upstream;
  var _rejected = false;
  var _promoting = false;
  static const _maxHeaderBytes = 64 * 1024;

  void start() {
    // Single subscription for the connection lifetime — its handler switches
    // from header-sniffing to byte-forwarding once the token is validated (a
    // single-subscription Socket cannot be re-listened after cancel).
    socket.listen(
      _onData,
      onError: (_) => _abort(),
      onDone: () {
        _upstream?.destroy();
        onDone();
      },
      cancelOnError: true,
    );
  }

  void _onData(List<int> data) {
    if (_rejected) return;
    final upstream = _upstream;
    if (upstream != null) {
      upstream.add(data); // already promoted → forward
      return;
    }
    _buf.addAll(data);
    if (_promoting) return; // buffering until upstream connects
    final headerEnd = _indexOfHeaderEnd(_buf);
    if (headerEnd == -1) {
      if (_buf.length > _maxHeaderBytes) _reject();
      return; // wait for the rest of the headers
    }
    final headerText = String.fromCharCodes(_buf.sublist(0, headerEnd));
    if (!_tokenMatches(headerText)) {
      _reject();
      return;
    }
    _promoting = true;
    _promote();
  }

  bool _tokenMatches(String headerText) {
    for (final line in headerText.split('\r\n')) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final name = line.substring(0, idx).trim().toLowerCase();
      if (name == teammateBusTokenHeader.toLowerCase()) {
        return line.substring(idx + 1).trim() == token;
      }
    }
    return false;
  }

  /// Token OK → connect upstream, flush the buffered bytes, pipe upstream→client
  /// (client→upstream is forwarded by [_onData] once [_upstream] is set).
  Future<void> _promote() async {
    final Socket upstream;
    try {
      upstream = await Socket.connect(InternetAddress.loopbackIPv4, upstreamPort);
    } on Object {
      socket.destroy();
      onDone();
      return;
    }
    upstream.add(_buf);
    _buf.clear();
    _upstream = upstream;
    upstream.listen(
      socket.add,
      onError: (_) => socket.destroy(),
      onDone: () {
        socket.destroy();
        onDone();
      },
      cancelOnError: true,
    );
  }

  void _reject() {
    _rejected = true;
    try {
      socket.write(
        'HTTP/1.1 403 Forbidden\r\n'
        'content-length: 0\r\n'
        'connection: close\r\n\r\n',
      );
      // close() flushes the response then half-closes; destroy() would drop it.
      unawaited(socket.close().whenComplete(onDone));
    } on Object {
      socket.destroy();
      onDone();
    }
  }

  void _abort() {
    _upstream?.destroy();
    socket.destroy();
    onDone();
  }

  static int _indexOfHeaderEnd(List<int> buf) {
    // find "\r\n\r\n"
    for (var i = 0; i + 3 < buf.length; i++) {
      if (buf[i] == 0x0d &&
          buf[i + 1] == 0x0a &&
          buf[i + 2] == 0x0d &&
          buf[i + 3] == 0x0a) {
        return i;
      }
    }
    return -1;
  }
}
