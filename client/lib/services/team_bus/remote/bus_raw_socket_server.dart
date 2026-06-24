import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../utils/logger.dart';
import '../cancellation.dart';
import '../mcp/jsonrpc.dart';
import '../mcp/teammate_bus_mcp_handler.dart';

/// Loopback raw-socket transport for the teammate bus, used by **remote**
/// members reaching the local bus through an SSH reverse tunnel.
///
/// Frames are line-delimited JSON (one JSON object per `\n`), the same wire
/// shape as stdio MCP. The first line must be a handshake
/// `{"token":"<sessionToken>","memberId":"<id>"}`; a missing/wrong token drops
/// the connection (the tunnel's remote `127.0.0.1:<P>` is visible to every
/// local user on the remote host). Subsequent lines are JSON-RPC dispatched
/// through the shared [TeammateBusMcpHandler] (same handler as the HTTP path —
/// only the framing differs), including the blocking `wait_for_message`.
class BusRawSocketServer {
  BusRawSocketServer({required this.handler, required this.token});

  final TeammateBusMcpHandler handler;
  final String token;

  ServerSocket? _server;
  final Set<CancellationToken> _activeWaits = <CancellationToken>{};

  int get port => _server!.port;

  Future<int> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_onSocket);
    return server.port;
  }

  Future<void> close() async {
    for (final cancel in _activeWaits.toList()) {
      cancel.cancel();
    }
    await _server?.close();
    _server = null;
  }

  void _onSocket(Socket socket) {
    final session = _SocketSession(socket, this);
    session.start();
  }
}

/// Per-connection state machine: handshake → line-delimited JSON-RPC dispatch.
class _SocketSession {
  _SocketSession(this._socket, this._server);

  final Socket _socket;
  final BusRawSocketServer _server;
  final List<int> _buf = <int>[];
  bool _authed = false;
  String _memberId = '';
  bool _closed = false;

  // Process one line at a time so a blocking wait_for_message doesn't interleave
  // with the next request (stdio MCP is request/response sequential).
  Future<void> _chain = Future<void>.value();
  final CancellationToken _socketCancel = CancellationToken();

  void start() {
    _socket.listen(
      _onData,
      onError: (_) => _shutdown(),
      onDone: _shutdown,
      cancelOnError: true,
    );
  }

  void _onData(List<int> data) {
    _buf.addAll(data);
    var nl = _buf.indexOf(0x0a);
    while (nl != -1) {
      final lineBytes = _buf.sublist(0, nl);
      _buf.removeRange(0, nl + 1);
      final line = utf8.decode(lineBytes, allowMalformed: true).trim();
      if (line.isNotEmpty) {
        _chain = _chain.then((_) => _handleLine(line));
      }
      nl = _buf.indexOf(0x0a);
    }
  }

  Future<void> _handleLine(String line) async {
    if (_closed) return;
    if (!_authed) {
      _handshake(line);
      return;
    }
    final req = JsonRpcRequest.tryParse(line);
    if (req == null) return;
    try {
      if (req.isNotification) {
        await _server.handler.handle(_memberId, req); // side effects only
        return;
      }
      if (_server.handler.isLongRunning(req)) {
        await _streamWait(req);
        return;
      }
      final res = await _server.handler.handle(_memberId, req);
      if (res != null) _writeLine(res.encode());
    } on Object catch (e, st) {
      appLogger.e('[bus-raw-socket] dispatch failed', error: e, stackTrace: st);
    }
  }

  void _handshake(String line) {
    Map<String, Object?>? hs;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, Object?>) hs = decoded;
    } on Object {
      hs = null;
    }
    final token = (hs?['token'] as String?)?.trim() ?? '';
    final member = (hs?['memberId'] as String?)?.trim() ?? '';
    if (token.isEmpty || token != _server.token || member.isEmpty) {
      _shutdown(); // reject: bad token / no member
      return;
    }
    _authed = true;
    _memberId = member;
  }

  Future<void> _streamWait(JsonRpcRequest req) async {
    final cancel = _socketCancel;
    _server._activeWaits.add(cancel);
    try {
      final delivery = await _server.handler.beginWait(
        _memberId,
        req,
        cancel: cancel,
      );
      if (cancel.isCancelled || _closed) {
        delivery.abort();
        return;
      }
      try {
        _writeLine(delivery.response.encode());
        await delivery.confirm();
      } on Object {
        delivery.abort();
      }
    } finally {
      _server._activeWaits.remove(cancel);
    }
  }

  void _writeLine(String s) {
    if (_closed) return;
    try {
      _socket.add(utf8.encode('$s\n'));
    } on Object {
      _shutdown();
    }
  }

  void _shutdown() {
    if (_closed) return;
    _closed = true;
    if (!_socketCancel.isCancelled) _socketCancel.cancel();
    try {
      _socket.destroy();
    } on Object {
      // already gone
    }
  }
}
