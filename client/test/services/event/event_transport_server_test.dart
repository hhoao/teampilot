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

  test('oversize line after handshake closes the connection', () async {
    final h = _Harness();
    await h.start();
    addTearDown(h.dispose);

    final socket = await Socket.connect('127.0.0.1', await h.port());
    final client = _LineClient(socket);
    addTearDown(client.destroy);

    await client.subscribe();
    await client.waitUntilSnapshotEnd();

    socket.add(Uint8List(eventTransportMaxLineBytes + 1));
    await socket.flush();
    await _waitFor(() => client.closed, timeout: const Duration(seconds: 2));
    expect(client.closed, isTrue);
  });
}
