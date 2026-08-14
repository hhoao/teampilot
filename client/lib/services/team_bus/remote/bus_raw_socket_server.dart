import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../utils/logging/logger.dart';
import '../cancellation.dart';
import '../mcp/jsonrpc.dart';
import '../mcp/mcp_method.dart';
import '../mcp/teammate_bus_mcp_handler.dart';
import '../mcp/teammate_bus_session_registry.dart';

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
///
/// At most one live socket per `(token, memberId)`: a newer handshake displaces
/// the prior connection so SSH tunnel flaps cannot leave a zombie waiter that
/// steals mail while the CLI's in-flight `wait_for_message` hangs with no reply.
class BusRawSocketServer {
  BusRawSocketServer({
    required TeammateBusMcpHandler handler,
    required String token,
  }) : _handler = handler,
       _token = token,
       _registry = null;

  BusRawSocketServer.multiplexed({required TeammateBusSessionRegistry registry})
    : _handler = null,
      _token = null,
      _registry = registry;

  final TeammateBusMcpHandler? _handler;
  final String? _token;
  final TeammateBusSessionRegistry? _registry;

  TeammateBusMcpHandler get handler => _handler!;
  String get token => _token!;

  TeammateBusMcpHandler? _handlerForToken(String token) {
    final sessionId = _registry!.sessionForToken(token);
    if (sessionId == null) return null;
    return _registry.handlerForSession(sessionId);
  }

  ServerSocket? _server;
  final Set<CancellationToken> _activeWaits = <CancellationToken>{};

  /// Live authed sessions keyed by [sessionKey] (`token\0memberId`).
  final Map<String, _SocketSession> _sessionsByKey = {};

  int get port => _server!.port;

  static String sessionKey(String token, String memberId) =>
      '$token\x00$memberId';

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
    for (final session in _sessionsByKey.values.toList()) {
      session.forceShutdown();
    }
    _sessionsByKey.clear();
    await _server?.close();
    _server = null;
  }

  void _onSocket(Socket socket) {
    final session = _SocketSession(socket, this);
    session.start();
  }

  /// Registers [session] for [key], displacing any prior live socket.
  void _attachSession(String key, _SocketSession session) {
    final prev = _sessionsByKey[key];
    if (prev != null && !identical(prev, session)) {
      prev.displace();
    }
    _sessionsByKey[key] = session;
  }

  void _detachSession(String key, _SocketSession session) {
    if (identical(_sessionsByKey[key], session)) {
      _sessionsByKey.remove(key);
    }
  }
}

/// Per-connection state machine: handshake → line-delimited JSON-RPC dispatch.
///
/// Matches [teammate_bus_bridge]: long `wait_for_message` must not stall the
/// read loop. Claude overlaps short tools / `notifications/cancelled` with an
/// in-flight wait; serializing them behind wait makes every MCP call look dead.
class _SocketSession {
  _SocketSession(this._socket, this._server);

  final Socket _socket;
  final BusRawSocketServer _server;
  final List<int> _buf = <int>[];
  bool _authed = false;
  String _memberId = '';
  String _sessionKey = '';
  TeammateBusMcpHandler? _handler;
  bool _closed = false;

  /// After [displace], shut down once in-flight waits have written errors.
  bool _pendingShutdown = false;
  int _inflightWaitCount = 0;

  final Set<CancellationToken> _sessionWaits = {};

  /// Serialize stdout writes so concurrent responses do not interleave bytes.
  Future<void> _writeLock = Future<void>.value();
  final CancellationToken _socketCancel = CancellationToken();

  void start() {
    _socket.listen(
      _onData,
      onError: (_) => forceShutdown(),
      onDone: forceShutdown,
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
        // Handshake must run before any tool dispatch on this socket.
        if (!_authed) {
          _handshake(line);
        } else {
          // Do not await: wait_for_message must not block cancel / short tools.
          unawaited(_dispatchLine(line));
        }
      }
      nl = _buf.indexOf(0x0a);
    }
  }

  Future<void> _dispatchLine(String line) async {
    if (_closed) return;
    final req = JsonRpcRequest.tryParse(line);
    if (req == null) return;
    final handler = _handler;
    if (handler == null) return;
    try {
      if (req.isNotification) {
        // Cancel notifications must reach WaitCancelRegistry while wait parks.
        await handler.handle(_memberId, req);
        return;
      }
      if (handler.isLongRunning(req)) {
        await _streamWait(req, handler);
        return;
      }
      final res = await handler.handle(_memberId, req);
      if (res != null) await _writeLine(res.encode());
    } on Object catch (e, st) {
      appLogger.e('[bus-raw-socket] dispatch failed', error: e, stackTrace: st);
    }
  }

  void _handshake(String line) {
    Map<String, Object?>? hs;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map) {
        hs = Map<String, Object?>.from(decoded);
      }
    } on Object {
      hs = null;
    }
    final token = (hs?['token'] as String?)?.trim() ?? '';
    final member = (hs?['memberId'] as String?)?.trim() ?? '';
    if (token.isEmpty || member.isEmpty) {
      forceShutdown();
      return;
    }

    final TeammateBusMcpHandler? handler;
    if (_server._registry != null) {
      handler = _server._handlerForToken(token);
    } else if (token != _server._token) {
      handler = null;
    } else {
      handler = _server._handler;
    }
    if (handler == null) {
      forceShutdown(); // reject: bad token / no member
      return;
    }
    _authed = true;
    _memberId = member;
    _sessionKey = BusRawSocketServer.sessionKey(token, member);
    _handler = handler;
    _server._attachSession(_sessionKey, this);
    appLogger.d(
      '[bus-raw-socket] session open member=$member',
    );
  }

  /// Newer handshake for the same member — cancel in-flight waits, reply, close.
  void displace() {
    if (_closed) return;
    if (_sessionWaits.isNotEmpty) {
      _pendingShutdown = true;
      for (final wait in _sessionWaits.toList()) {
        if (!wait.isCancelled) {
          wait.cancel(WaitCancelReason.disconnected);
        }
      }
      return;
    }
    forceShutdown();
  }

  Future<void> _streamWait(
    JsonRpcRequest req,
    TeammateBusMcpHandler handler,
  ) async {
    final cancel = CancellationToken();
    _sessionWaits.add(cancel);
    _inflightWaitCount++;
    _server._activeWaits.add(cancel);

    // Socket death must unblock receiveWork (otherwise park leaks until mail).
    void onSocketGone() {
      if (!cancel.isCancelled) {
        cancel.cancel(WaitCancelReason.disconnected);
      }
    }

    if (_socketCancel.isCancelled) {
      onSocketGone();
    } else {
      unawaited(_socketCancel.whenCancelled.then((_) => onSocketGone()));
    }

    handler.waitCancels.register(req.id, cancel, memberId: _memberId);
    appLogger.d(
      '[bus-raw-socket] wait open member=$_memberId id=${req.id}',
    );
    try {
      final delivery = await handler.beginWait(_memberId, req, cancel: cancel);
      if (cancel.isCancelled || _closed) {
        delivery.abort();
        await _replyWaitCancelled(req, cancel);
        return;
      }
      try {
        await _writeLine(delivery.response.encode());
        if (cancel.isCancelled || _closed) {
          delivery.abort();
          // Response bytes may be lost; prefer redeliver over silent confirm.
        } else {
          await delivery.confirm();
          appLogger.d(
            '[bus-raw-socket] wait delivered member=$_memberId id=${req.id}',
          );
        }
      } on Object {
        delivery.abort();
      }
    } finally {
      _sessionWaits.remove(cancel);
      _inflightWaitCount--;
      handler.waitCancels.unregister(
        req.id,
        memberId: _memberId,
        cancel: cancel,
      );
      _server._activeWaits.remove(cancel);
      if (_pendingShutdown && _inflightWaitCount <= 0) {
        forceShutdown();
      }
    }
  }

  Future<void> _replyWaitCancelled(
    JsonRpcRequest req,
    CancellationToken cancel,
  ) async {
    if (_closed) return;
    final message = switch (cancel.cancelReason) {
      WaitCancelReason.superseded =>
        'wait_for_message superseded by a newer wait',
      WaitCancelReason.disconnected =>
        'wait_for_message cancelled (disconnected)',
      WaitCancelReason.mcpCancelled => 'wait_for_message cancelled',
      null => 'wait_for_message cancelled',
    };
    await _writeLine(
      JsonRpcResponse.error(
        req.id,
        JsonRpcErrorCode.serverError,
        message,
      ).encode(),
    );
    appLogger.d(
      '[bus-raw-socket] wait cancelled member=$_memberId id=${req.id} '
      'reason=${cancel.cancelReason?.name}',
    );
  }

  Future<void> _writeLine(String s) {
    final done = Completer<void>();
    _writeLock = _writeLock.then((_) async {
      try {
        if (_closed) return;
        try {
          _socket.add(utf8.encode('$s\n'));
        } on Object {
          forceShutdown();
        }
      } finally {
        if (!done.isCompleted) done.complete();
      }
    });
    return done.future;
  }

  /// Immediate teardown (peer gone / server close / post-displace).
  void forceShutdown() {
    if (_closed) return;
    final member = _memberId;
    _closed = true;
    _pendingShutdown = false;
    if (_sessionKey.isNotEmpty) {
      _server._detachSession(_sessionKey, this);
    }
    if (!_socketCancel.isCancelled) {
      _socketCancel.cancel(WaitCancelReason.disconnected);
    }
    for (final wait in _sessionWaits.toList()) {
      if (!wait.isCancelled) {
        wait.cancel(WaitCancelReason.disconnected);
      }
    }
    if (member.isNotEmpty) {
      appLogger.d('[bus-raw-socket] session close member=$member');
    }
    try {
      _socket.destroy();
    } on Object {
      // already gone
    }
  }
}
