import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';
import 'package:teampilot/services/event/agent_presence_projection.dart';
import 'package:teampilot/services/event/agent_presence_transport_codec.dart';
import 'package:teampilot/services/event/async_dispatcher.dart';
import 'package:teampilot/services/event/event_transport_codec.dart';
import 'package:teampilot/services/event/event_transport_server.dart';
import 'package:teampilot/services/event/session_lifecycle_transport_codec.dart';
import 'package:teampilot/services/storage/app_paths.dart';

import '../../support/in_memory_filesystem.dart';

const _adPath = '/tp/event-transport.json';

Future<void> _waitFor(
  bool Function() done, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _Harness {
  _Harness({
    this.subscribeTimeout = const Duration(seconds: 5),
    DateTime Function()? clock,
    int Function()? pid,
    this.bind,
  }) : dispatcher = AsyncDispatcher()..start(),
       presence = AgentPresenceProjection(),
       fs = InMemoryFilesystem(),
       clock = clock ?? (() => DateTime.utc(2026, 9, 12)),
       pid = pid ?? (() => 4242);

  final AsyncDispatcher dispatcher;
  final AgentPresenceProjection presence;
  final InMemoryFilesystem fs;
  final Duration subscribeTimeout;
  final DateTime Function() clock;
  final int Function() pid;
  final Future<ServerSocket> Function(InternetAddress host, int port)? bind;
  late final EventTransportServer server;

  Future<void> start() async {
    server = EventTransportServer(
      dispatcher: dispatcher,
      presence: presence,
      fs: fs,
      advertisementPath: _adPath,
      codecs: [AgentPresenceTransportCodec(), SessionLifecycleTransportCodec()],
      subscribeTimeout: subscribeTimeout,
      clock: clock,
      pid: pid,
      bind: bind,
    );
    await server.start();
  }

  Future<Map<String, Object?>> advertisement() async {
    final raw = await fs.readString(_adPath);
    expect(raw, isNotNull);
    return jsonDecode(raw!) as Map<String, Object?>;
  }

  Future<int> port() async => (await advertisement())['port']! as int;

  Future<void> dispose() async {
    await server.stop();
    await dispatcher.stop();
    await presence.close();
  }
}

class _LineClient {
  _LineClient(this.socket) {
    _closed = Completer<void>();
    _sub = utf8.decoder
        .bind(socket)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.trim().isEmpty) return;
            final decoded = jsonDecode(line);
            if (decoded is Map) {
              lines.add({
                for (final e in decoded.entries) e.key.toString(): e.value,
              });
            }
          },
          onDone: () {
            if (!_closed.isCompleted) _closed.complete();
          },
          onError: (_) {
            if (!_closed.isCompleted) _closed.complete();
          },
        );
  }

  final Socket socket;
  final lines = <Map<String, Object?>>[];
  late final StreamSubscription<String> _sub;
  late final Completer<void> _closed;

  Future<void> get done => _closed.future;

  bool get closed => _closed.isCompleted;

  Future<void> subscribe({
    List<String> families = const ['agentPresence', 'nope'],
  }) async {
    socket.add(
      utf8.encode(
        encodeTransportLine({
          'v': 1,
          'type': 'subscribe',
          'families': families,
        }),
      ),
    );
    await socket.flush();
  }

  Future<void> waitUntilSnapshotEnd() async {
    await _waitFor(() => lines.any((l) => l['type'] == 'snapshotEnd'));
    expect(
      lines.any((l) => l['type'] == 'snapshotEnd'),
      isTrue,
      reason: 'timed out waiting for snapshotEnd',
    );
  }

  Future<void> destroy() async {
    await _sub.cancel();
    socket.destroy();
  }
}

void main() {
  test('start writes a loopback advertisement with a live port', () async {
    final h = _Harness();
    await h.start();
    addTearDown(h.dispose);

    expect(const AppPaths('/tp').eventTransportJson, _adPath);
    expect(AppPaths.eventTransportJsonForTeampilotRoot('/tp'), _adPath);

    final ad = await h.advertisement();
    expect(ad['v'], eventTransportProtocolVersion);
    expect(ad['bindHost'], '127.0.0.1');
    expect(ad['port'], greaterThan(0));
    expect(ad['pid'], 4242);
    expect(ad['startedAt'], '2026-09-12T00:00:00.000Z');
  });

  test('subscribe intersects families and omits unknown ones', () async {
    final h = _Harness();
    await h.start();
    addTearDown(h.dispose);

    final socket = await Socket.connect('127.0.0.1', await h.port());
    final client = _LineClient(socket);
    addTearDown(client.destroy);

    await client.subscribe();
    await client.waitUntilSnapshotEnd();

    final subscribed = client.lines.firstWhere(
      (l) => l['type'] == 'subscribed',
    );
    expect(subscribed['families'], ['agentPresence']);
  });

  test('presence snapshot is begin, one set, then end', () async {
    final h = _Harness();
    h.presence.handle(
      AgentPresenceEvent(
        seat: const PresenceSeatKey(sessionId: 's', memberId: 'dev'),
        eventKind: AgentPresenceKind.working,
        timestamp: DateTime.utc(2026, 9, 11),
      ),
    );
    await h.start();
    addTearDown(h.dispose);

    final socket = await Socket.connect('127.0.0.1', await h.port());
    final client = _LineClient(socket);
    addTearDown(client.destroy);

    await client.subscribe();
    await client.waitUntilSnapshotEnd();

    expect(client.lines[0]['type'], 'subscribed');
    expect(client.lines[1], {
      'v': 1,
      'type': 'snapshotBegin',
      'family': 'agentPresence',
    });
    expect(client.lines[2]['type'], 'event');
    expect(client.lines[2]['family'], 'agentPresence');
    expect(client.lines[2]['op'], 'set');
    expect(client.lines[2]['kind'], 'working');
    expect(client.lines[2]['seat'], {'sessionId': 's', 'memberId': 'dev'});
    expect(client.lines[3]['type'], 'snapshotEnd');
    expect(client.lines[3]['family'], 'agentPresence');
  });

  test(
    'empty projection snapshot is begin immediately followed by end',
    () async {
      final h = _Harness();
      await h.start();
      addTearDown(h.dispose);

      final socket = await Socket.connect('127.0.0.1', await h.port());
      final client = _LineClient(socket);
      addTearDown(client.destroy);

      await client.subscribe();
      await client.waitUntilSnapshotEnd();

      final afterSub = client.lines.skip(1).toList();
      expect(afterSub[0]['type'], 'snapshotBegin');
      expect(afterSub[1]['type'], 'snapshotEnd');
      expect(afterSub.length, 2);
    },
  );

  test('two sockets both receive a later dispatched presence set', () async {
    final h = _Harness();
    await h.start();
    addTearDown(h.dispose);

    final port = await h.port();
    final a = _LineClient(await Socket.connect('127.0.0.1', port));
    final b = _LineClient(await Socket.connect('127.0.0.1', port));
    addTearDown(a.destroy);
    addTearDown(b.destroy);

    await a.subscribe();
    await b.subscribe();
    await a.waitUntilSnapshotEnd();
    await b.waitUntilSnapshotEnd();

    h.dispatcher.dispatch(
      AgentPresenceEvent(
        seat: const PresenceSeatKey(sessionId: 's', memberId: 'dev'),
        eventKind: AgentPresenceKind.idle,
        timestamp: DateTime.utc(2026, 9, 12, 1),
      ),
    );

    bool hasLiveSet(_LineClient c) => c.lines.any(
      (l) => l['type'] == 'event' && l['op'] == 'set' && l['kind'] == 'idle',
    );
    await _waitFor(() => hasLiveSet(a) && hasLiveSet(b));
    expect(hasLiveSet(a), isTrue);
    expect(hasLiveSet(b), isTrue);
  });

  test('subscribe timeout closes a silent connection', () async {
    final h = _Harness(subscribeTimeout: const Duration(milliseconds: 50));
    await h.start();
    addTearDown(h.dispose);

    final socket = await Socket.connect('127.0.0.1', await h.port());
    var closed = false;
    socket.listen(
      (_) {},
      onDone: () => closed = true,
      onError: (_) => closed = true,
    );
    addTearDown(socket.destroy);
    await _waitFor(() => closed, timeout: const Duration(seconds: 2));
    expect(closed, isTrue);
  });

  test('oversize first line before subscribe sends error then EOF', () async {
    final h = _Harness(
      bind: (host, port) async => _MappedServerSocket(
        await ServerSocket.bind(host, port),
        _AbortUnflushedSocket.new,
      ),
    );
    await h.start();
    addTearDown(h.dispose);

    final socket = await Socket.connect('127.0.0.1', await h.port());
    final client = _LineClient(socket);
    addTearDown(client.destroy);

    socket.add(Uint8List(eventTransportMaxLineBytes + 1));
    await socket.flush();
    await _waitFor(
      () => client.lines.any((l) => l['type'] == 'error') || client.closed,
      timeout: const Duration(seconds: 2),
    );
    expect(
      client.lines.any((l) => l['type'] == 'error' && l['code'] == 'oversize'),
      isTrue,
      reason: 'client must read {type: error, code: oversize} before EOF',
    );
    await _waitFor(() => client.closed, timeout: const Duration(seconds: 2));
    expect(client.closed, isTrue);
  });

  test('oversize line after handshake sends error then EOF', () async {
    final h = _Harness(
      bind: (host, port) async => _MappedServerSocket(
        await ServerSocket.bind(host, port),
        _AbortUnflushedSocket.new,
      ),
    );
    await h.start();
    addTearDown(h.dispose);

    final socket = await Socket.connect('127.0.0.1', await h.port());
    final client = _LineClient(socket);
    addTearDown(client.destroy);

    await client.subscribe();
    await client.waitUntilSnapshotEnd();

    socket.add(Uint8List(eventTransportMaxLineBytes + 1));
    await socket.flush();
    await _waitFor(
      () => client.lines.any((l) => l['type'] == 'error') || client.closed,
      timeout: const Duration(seconds: 2),
    );
    expect(
      client.lines.any((l) => l['type'] == 'error' && l['code'] == 'oversize'),
      isTrue,
      reason: 'client must read {type: error, code: oversize} before EOF',
    );
    await _waitFor(() => client.closed, timeout: const Duration(seconds: 2));
    expect(client.closed, isTrue);
  });

  test('a reset peer completing done with an error does not take down accept', () async {
    final wrappers = <_ErrorOnDoneSocket>[];
    final h = _Harness(
      bind: (host, port) async => _MappedServerSocket(
        await ServerSocket.bind(host, port),
        (socket) {
          final wrapped = _ErrorOnDoneSocket(socket);
          wrappers.add(wrapped);
          return wrapped;
        },
      ),
    );
    await h.start();
    addTearDown(h.dispose);

    final first = _LineClient(await Socket.connect('127.0.0.1', await h.port()));
    addTearDown(first.destroy);
    await first.subscribe();
    await first.waitUntilSnapshotEnd();
    await _waitFor(() => wrappers.isNotEmpty);

    wrappers.first.completeDoneWithError();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final second = _LineClient(
      await Socket.connect('127.0.0.1', await h.port()),
    );
    addTearDown(second.destroy);
    await second.subscribe();
    await second.waitUntilSnapshotEnd();
    expect(second.lines.any((l) => l['type'] == 'snapshotEnd'), isTrue);
  });

  test('stop closes the listen socket before tearing down handlers', () async {
    late _HoldUntilCloseServerSocket held;
    final h = _Harness(
      bind: (host, port) async {
        held = _HoldUntilCloseServerSocket(await ServerSocket.bind(host, port));
        return held;
      },
    );
    await h.start();
    addTearDown(h.dispose);

    final socket = await Socket.connect('127.0.0.1', await h.port());
    var closed = false;
    socket.listen(
      (_) {},
      onDone: () => closed = true,
      onError: (_) => closed = true,
    );
    addTearDown(socket.destroy);

    await _waitFor(() => held.heldCount == 1);
    expect(held.heldCount, 1);
    await h.server.stop();
    await _waitFor(() => closed, timeout: const Duration(seconds: 2));
    expect(
      closed,
      isTrue,
      reason: 'a connection accepted during stop must be destroyed',
    );
  });
}

/// Delegates a real socket except [done], which can be failed to model a RST.
final class _ErrorOnDoneSocket extends Stream<Uint8List> implements Socket {
  _ErrorOnDoneSocket(this._inner);

  final Socket _inner;
  final Completer<void> _done = Completer<void>();

  void completeDoneWithError([
    Object error = const SocketException('Connection reset by peer'),
  ]) {
    if (!_done.isCompleted) _done.completeError(error);
  }

  @override
  void add(List<int> data) => _inner.add(data);

  @override
  void write(Object? object) => _inner.write(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _inner.writeAll(objects, separator);

  @override
  void writeln([Object? object = '']) => _inner.writeln(object);

  @override
  void writeCharCode(int charCode) => _inner.writeCharCode(charCode);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future addStream(Stream<List<int>> stream) => _inner.addStream(stream);

  @override
  Future flush() => _inner.flush();

  @override
  Future close() => _inner.close();

  @override
  void destroy() => _inner.destroy();

  @override
  Future get done => _done.future;

  @override
  Encoding encoding = utf8;

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _inner.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) => _inner.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _inner.setRawOption(option);

  @override
  int get port => _inner.port;

  @override
  int get remotePort => _inner.remotePort;

  @override
  InternetAddress get address => _inner.address;

  @override
  InternetAddress get remoteAddress => _inner.remoteAddress;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _inner.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

/// Forwards an accepted socket, but [add] is delayed one microtask so
/// [destroy] in the same turn drops the send buffer (as OS destroy can).
final class _AbortUnflushedSocket extends Stream<Uint8List> implements Socket {
  _AbortUnflushedSocket(this._inner);

  final Socket _inner;
  final _queued = <List<int>>[];
  var _sendScheduled = false;
  var _dead = false;

  void _enqueue(List<int> data) {
    if (_dead) return;
    _queued.add(List<int>.from(data));
    if (_sendScheduled) return;
    _sendScheduled = true;
    // Event-queue delay so a later microtask destroy() (handshake
    // complete → _serve destroy) still drops the unflushed buffer.
    Future<void>.delayed(Duration.zero, () {
      _sendScheduled = false;
      if (_dead) {
        _queued.clear();
        return;
      }
      for (final chunk in _queued) {
        _inner.add(chunk);
      }
      _queued.clear();
    });
  }

  @override
  void add(List<int> data) => _enqueue(data);

  @override
  void write(Object? object) => _enqueue(utf8.encode('$object'));

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future flush() async {
    while (_queued.isNotEmpty && !_dead) {
      await Future<void>.delayed(Duration.zero);
    }
    if (!_dead) await _inner.flush();
  }

  @override
  Future close() async {
    await flush();
    if (!_dead) await _inner.close();
  }

  @override
  void destroy() {
    _dead = true;
    _queued.clear();
    _inner.destroy();
  }

  @override
  Future get done => _inner.done;

  @override
  Encoding encoding = utf8;

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _inner.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) => _inner.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _inner.setRawOption(option);

  @override
  int get port => _inner.port;

  @override
  int get remotePort => _inner.remotePort;

  @override
  InternetAddress get address => _inner.address;

  @override
  InternetAddress get remoteAddress => _inner.remoteAddress;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _inner.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

final class _MappedServerSocket extends Stream<Socket> implements ServerSocket {
  _MappedServerSocket(this._inner, this._map);

  final ServerSocket _inner;
  final Socket Function(Socket) _map;

  @override
  StreamSubscription<Socket> listen(
    void Function(Socket event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _inner
        .map(_map)
        .listen(
          onData,
          onError: onError,
          onDone: onDone,
          cancelOnError: cancelOnError,
        );
  }

  @override
  int get port => _inner.port;

  @override
  InternetAddress get address => _inner.address;

  @override
  Future<ServerSocket> close() async {
    await _inner.close();
    return this;
  }
}

/// Holds accepted sockets until [close], modeling an accept that lands in stop().
final class _HoldUntilCloseServerSocket extends Stream<Socket>
    implements ServerSocket {
  _HoldUntilCloseServerSocket(this._inner) {
    _sub = _inner.listen(
      _held.add,
      onError: _controller.addError,
      onDone: () {
        if (!_controller.isClosed) {
          unawaited(_controller.close());
        }
      },
    );
  }

  final ServerSocket _inner;
  final _held = <Socket>[];
  final _controller = StreamController<Socket>(sync: true);
  late final StreamSubscription<Socket> _sub;

  int get heldCount => _held.length;

  @override
  StreamSubscription<Socket> listen(
    void Function(Socket event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  int get port => _inner.port;

  @override
  InternetAddress get address => _inner.address;

  @override
  Future<ServerSocket> close() async {
    for (final client in List<Socket>.of(_held)) {
      if (!_controller.isClosed) {
        _controller.add(client);
      }
    }
    _held.clear();
    if (!_controller.isClosed) {
      await _controller.close();
    }
    await _sub.cancel();
    await _inner.close();
    return this;
  }
}
