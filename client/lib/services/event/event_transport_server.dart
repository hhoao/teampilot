import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import 'agent_presence_event.dart';
import 'agent_presence_projection.dart';
import 'dispatcher.dart';
import 'event_transport_codec.dart';
import 'session_lifecycle_event.dart';

/// Loopback NDJSON event transport: advertise, handshake, snapshot, fan-out.
final class EventTransportServer {
  EventTransportServer({
    required Dispatcher dispatcher,
    required AgentPresenceProjection presence,
    required Filesystem fs,
    required String advertisementPath,
    required List<EventTransportFamilyCodec> codecs,
    this.subscribeTimeout = const Duration(seconds: 5),
    DateTime Function()? clock,
    int Function()? pid,
    Future<ServerSocket> Function(InternetAddress host, int port)? bind,
  }) : _dispatcher = dispatcher,
       _presence = presence,
       _fs = fs,
       _advertisementPath = advertisementPath,
       _codecsByFamily = {for (final c in codecs) c.family: c},
       _clock = clock ?? DateTime.now,
       _pid = pid ?? _currentPid,
       _bind = bind;

  static const _tag = 'event-transport';

  final Dispatcher _dispatcher;
  final AgentPresenceProjection _presence;
  final Filesystem _fs;
  final String _advertisementPath;
  final Map<String, EventTransportFamilyCodec> _codecsByFamily;
  final Duration subscribeTimeout;
  final DateTime Function() _clock;
  final int Function() _pid;
  final Future<ServerSocket> Function(InternetAddress host, int port)? _bind;

  ServerSocket? _socket;
  Future<void>? _accept;
  final Set<_ConnectionHandler> _handlers = {};

  static int _currentPid() => pid;

  Future<void> start() async {
    _socket = await (_bind ?? ServerSocket.bind)(
      InternetAddress.loopbackIPv4,
      0,
    );
    await _fs.writeString(
      _advertisementPath,
      jsonEncode({
        'v': eventTransportProtocolVersion,
        'bindHost': '127.0.0.1',
        'port': _socket!.port,
        'pid': _pid(),
        'startedAt': _clock().toUtc().toIso8601String(),
      }),
    );
    final socket = _socket!;
    _accept = () async {
      try {
        await for (final client in socket) {
          unawaited(_serve(client));
        }
      } on Object {
        // Closed via [stop].
      }
    }();
  }

  Future<void> stop() async {
    final socket = _socket;
    _socket = null;
    await socket?.close();
    await _accept;
    _accept = null;
    for (final handler in List<_ConnectionHandler>.of(_handlers)) {
      _dispatcher.unregister(handler);
      handler.socket.destroy();
    }
    try {
      await _fs.removeRecursive(_advertisementPath);
    } on Object catch (error, stackTrace) {
      appLogger.d(
        '$_tag advertisement remove failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _serve(Socket client) async {
    try {
      client.setOption(SocketOption.tcpNoDelay, true);
    } on Object {
      // Best-effort; some fakes / platforms reject the option.
    }
    final handler = _ConnectionHandler(socket: client, codecs: _codecsByFamily);
    _handlers.add(handler);
    final session = _ClientSession(client);
    session.start();
    try {
      final requested = await _readSubscribe(session);
      if (requested == null) {
        if (!session.oversizeClosing) {
          client.destroy();
        }
        return;
      }
      final families = requested
          .toSet()
          .intersection(_codecsByFamily.keys.toSet())
          .toList();
      _writeJson(client, {
        'v': eventTransportProtocolVersion,
        'type': 'subscribed',
        'families': families,
      });
      final snapshot = Map<PresenceSeatKey, AgentPresenceKind>.of(
        _presence.snapshot,
      );
      if (families.contains(eventTransportFamilyAgentPresence)) {
        _dispatcher.registerFamily<AgentPresenceKind>(
          AgentPresenceKind.working.runtimeType,
          handler,
        );
      }
      if (families.contains(eventTransportFamilySessionLifecycle)) {
        _dispatcher.registerFamily<SessionLifecycleKind>(
          SessionLifecycleKind.sessionStarted.runtimeType,
          handler,
        );
      }
      if (families.contains(eventTransportFamilyAgentPresence)) {
        _writePresenceSnapshot(client, snapshot);
      }
      session.handshakeComplete = true;
      session.drain();
      try {
        await client.done;
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '$_tag client done failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    } finally {
      _handlers.remove(handler);
      _dispatcher.unregister(handler);
      if (!session.oversizeClosing) {
        client.destroy();
      }
    }
  }

  Future<List<String>?> _readSubscribe(_ClientSession session) {
    return Future.any<List<String>?>([
      session.handshake.future,
      Future<List<String>?>.delayed(subscribeTimeout, () => null),
    ]);
  }

  void _writePresenceSnapshot(
    Socket client,
    Map<PresenceSeatKey, AgentPresenceKind> snapshot,
  ) {
    _writeJson(client, {
      'v': eventTransportProtocolVersion,
      'type': 'snapshotBegin',
      'family': eventTransportFamilyAgentPresence,
    });
    final presenceCodec = _codecsByFamily[eventTransportFamilyAgentPresence]!;
    for (final e in snapshot.entries) {
      _writeJson(client, {
        'v': eventTransportProtocolVersion,
        'type': 'event',
        'family': eventTransportFamilyAgentPresence,
        ...presenceCodec.encode(
          AgentPresenceEvent(
            seat: e.key,
            eventKind: e.value,
            timestamp: _clock(),
          ),
        ),
      });
    }
    _writeJson(client, {
      'v': eventTransportProtocolVersion,
      'type': 'snapshotEnd',
      'family': eventTransportFamilyAgentPresence,
    });
  }
}

void _writeJson(Socket client, Map<String, Object?> object) {
  try {
    client.add(utf8.encode(encodeTransportLine(object)));
  } on Object catch (error, stackTrace) {
    appLogger.e(
      '${EventTransportServer._tag} write failed',
      error: error,
      stackTrace: stackTrace,
      recordError: false,
    );
  }
}

void _writeOversize(Socket client) {
  _writeJson(client, {
    'v': eventTransportProtocolVersion,
    'type': 'error',
    'code': 'oversize',
    'message': 'line exceeds $eventTransportMaxLineBytes bytes',
  });
}

Future<void> _flushThenClose(Socket socket) async {
  try {
    await socket.flush();
    await socket.close();
  } on Object {
    try {
      socket.destroy();
    } on Object {
      // already gone
    }
  }
}

/// Per-connection byte assembler: first line is subscribe; later oversize closes.
final class _ClientSession {
  _ClientSession(this.socket);

  final Socket socket;
  final List<int> buffer = <int>[];
  final Completer<List<String>?> handshake = Completer<List<String>?>();
  var handshakeComplete = false;
  var oversizeClosing = false;
  var _closed = false;

  void start() {
    socket.listen(
      _onData,
      onDone: _failHandshake,
      onError: (_, __) => _failHandshake(),
      cancelOnError: true,
    );
  }

  void drain() => _onData(const <int>[]);

  void _onData(List<int> data) {
    if (_closed) return;
    if (data.isNotEmpty) buffer.addAll(data);
    if (!handshake.isCompleted) {
      _readHandshake();
      return;
    }
    if (handshakeComplete) _checkPostHandshake();
  }

  void _readHandshake() {
    if (_oversizeWithoutNewline()) return;
    final nl = buffer.indexOf(10);
    if (nl < 0) return;
    if (nl > eventTransportMaxLineBytes) {
      _oversize();
      return;
    }
    final line = utf8.decode(buffer.sublist(0, nl + 1));
    buffer.removeRange(0, nl + 1);
    final decoded = tryDecodeTransportLine(line);
    if (decoded == null || decoded['type'] != 'subscribe') {
      _completeHandshake(null);
      return;
    }
    _completeHandshake(_parseFamilies(decoded['families']));
  }

  void _checkPostHandshake() {
    while (!_closed) {
      if (_oversizeWithoutNewline()) return;
      final nl = buffer.indexOf(10);
      if (nl < 0) return;
      if (nl > eventTransportMaxLineBytes) {
        _oversize();
        return;
      }
      buffer.removeRange(0, nl + 1);
    }
  }

  bool _oversizeWithoutNewline() {
    if (buffer.contains(10)) return false;
    if (!transportLineTooLong(buffer)) return false;
    _oversize();
    return true;
  }

  void _oversize() {
    _writeOversize(socket);
    oversizeClosing = true;
    _closed = true;
    _completeHandshake(null);
    unawaited(_flushThenClose(socket));
  }

  void _failHandshake() => _completeHandshake(null);

  void _completeHandshake(List<String>? families) {
    if (!handshake.isCompleted) handshake.complete(families);
  }
}

List<String> _parseFamilies(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is String) item,
  ];
}

final class _ConnectionHandler implements EventHandler<DispatcherEvent> {
  _ConnectionHandler({required this.socket, required this.codecs});

  final Socket socket;
  final Map<String, EventTransportFamilyCodec> codecs;

  @override
  void handle(DispatcherEvent event) {
    try {
      final codec = _codecFor(event);
      if (codec == null) return;
      _writeJson(socket, {
        'v': eventTransportProtocolVersion,
        'type': 'event',
        'family': codec.family,
        ...codec.encode(event),
      });
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '${EventTransportServer._tag} write failed',
        error: error,
        stackTrace: stackTrace,
        recordError: false,
      );
    }
  }

  EventTransportFamilyCodec? _codecFor(DispatcherEvent event) {
    if (event is AgentPresenceEvent) {
      return codecs[eventTransportFamilyAgentPresence];
    }
    if (event is SessionLifecycleEvent) {
      return codecs[eventTransportFamilySessionLifecycle];
    }
    return null;
  }
}
