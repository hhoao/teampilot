import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Keep-alive for spliced sockets; idle SSH traffic still flows frames.
const pingInterval = Duration(seconds: 20);

/// How long a dial waits for its desktop to open /splice before cleanup.
const pendingSpliceTtl = Duration(seconds: 30);

/// One registered desktop per [hostId]: the newest /register wins.
///
/// Wire keys mirror the client's `connect_relay_protocol.dart`, reimplemented
/// here on purpose: the relay stays dependency-free and must never grow a
/// path back into the TeamPilot client tree.
///
/// The relay is a dumb byte pipe. It selects a channel from the dial query
/// and splices sockets; it does not parse SSH or pairing JSON, does not
/// decide authorization, and never logs the opaque credentials it forwards.
class RelayServer {
  final Map<String, WebSocket> _desktops = {};
  final Map<String, _PendingSplice> _pending = {};
  HttpServer? _server;
  Timer? _sweeper;
  var _nextSpliceId = 0;

  int get port => _server?.port ?? 0;

  Future<void> start({Object address = '0.0.0.0', int port = 2769}) async {
    final server = await HttpServer.bind(address, port);
    _server = server;
    _sweeper = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _sweepExpired(),
    );
    server.listen(_onRequest, onError: (Object _) {});
  }

  Future<void> stop() async {
    _sweeper?.cancel();
    for (final desktop in _desktops.values) {
      unawaited(desktop.close());
    }
    _desktops.clear();
    for (final pending in _pending.values) {
      pending.phone.close();
    }
    _pending.clear();
    await _server?.close(force: true);
    _server = null;
  }

  void _onRequest(HttpRequest request) {
    unawaited(_route(request));
  }

  Future<void> _route(HttpRequest request) async {
    switch (request.uri.path) {
      case '/health':
        request.response.statusCode = HttpStatus.ok;
        request.response.write('ok');
        await request.response.close();
      case '/register':
        await _onRegister(request);
      case '/dial':
        await _onDial(request);
      case '/splice':
        await _onSplice(request);
      default:
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
    }
  }

  Future<void> _onRegister(HttpRequest request) async {
    final hostId = request.uri.queryParameters['hostId'];
    if (hostId == null || hostId.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    socket.pingInterval = pingInterval;
    _desktops[hostId]?.close();
    _desktops[hostId] = socket;
    unawaited(
      socket.done.whenComplete(() {
        if (identical(_desktops[hostId], socket)) {
          _desktops.remove(hostId);
        }
      }),
    );
  }

  Future<void> _onDial(HttpRequest request) async {
    final query = request.uri.queryParameters;
    final hostId = query['hostId'];
    final channel = query['channel'] ?? '';
    final desktop = hostId == null ? null : _desktops[hostId];
    if (channel.isEmpty || desktop == null) {
      // No registered desktop: reject before upgrading so the phone sees a
      // failed dial immediately.
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    final spliceId = _mintSpliceId();
    final notification = <String, Object?>{
      'type': 'dial',
      'channel': channel,
      'spliceId': spliceId,
      if (query['deviceId']?.isNotEmpty == true) 'deviceId': query['deviceId'],
      // Forward the opaque credential unchanged; only the desktop validates it.
      if (query['inviteToken']?.isNotEmpty == true)
        'inviteToken': query['inviteToken'],
      if (query['relayGrant']?.isNotEmpty == true)
        'relayGrant': query['relayGrant'],
    };
    try {
      desktop.add(jsonEncode(notification));
    } on Object {
      if (identical(_desktops[hostId], desktop)) {
        _desktops.remove(hostId);
      }
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    final phone = await WebSocketTransformer.upgrade(request);
    phone.pingInterval = pingInterval;
    _pending[spliceId] = _PendingSplice(phone: phone);
  }

  Future<void> _onSplice(HttpRequest request) async {
    final id = request.uri.queryParameters['id'];
    final pending = id == null ? null : _pending.remove(id);
    if (pending == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final desktopSocket = await WebSocketTransformer.upgrade(request);
    desktopSocket.pingInterval = pingInterval;
    _splice(pending.phone, desktopSocket);
  }

  String _mintSpliceId() {
    _nextSpliceId += 1;
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
        '${_nextSpliceId.toRadixString(36)}';
  }

  void _sweepExpired() {
    final now = DateTime.now();
    for (final entry in Map.of(_pending).entries) {
      if (now.difference(entry.value.createdAt) > pendingSpliceTtl) {
        _pending.remove(entry.key);
        entry.value.phone.close();
      }
    }
  }
}

void _splice(WebSocket phone, WebSocket desktopSocket) {
  phone.listen(
    desktopSocket.add,
    onDone: () => desktopSocket.close(),
    onError: (Object _) => desktopSocket.close(),
    cancelOnError: true,
  );
  desktopSocket.listen(
    phone.add,
    onDone: () => phone.close(),
    onError: (Object _) => phone.close(),
    cancelOnError: true,
  );
}

class _PendingSplice {
  _PendingSplice({required this.phone});

  final WebSocket phone;
  final DateTime createdAt = DateTime.now();
}
