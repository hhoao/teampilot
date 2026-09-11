import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';
import 'package:teampilot/services/event/agent_presence_projection.dart';
import 'package:teampilot/services/event/agent_presence_transport_codec.dart';
import 'package:teampilot/services/event/async_dispatcher.dart';
import 'package:teampilot/services/event/event_transport_client.dart';
import 'package:teampilot/services/event/event_transport_codec.dart';
import 'package:teampilot/services/event/session_lifecycle_transport_codec.dart';

Future<void> _waitFor(
  bool Function() ok, {
  required Duration timeout,
}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) {
      fail('timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

const _timeout = Duration(seconds: 2);
const _seat = PresenceSeatKey(sessionId: 's', memberId: 'dev');

final class _FakeChannel implements EventTransportByteChannel {
  final inbound = StreamController<List<int>>();
  final outbound = <int>[];
  var closed = false;

  @override
  Stream<List<int>> get incoming => inbound.stream;

  @override
  void add(List<int> data) => outbound.addAll(data);

  @override
  Future<void> close() async {
    closed = true;
    if (!inbound.isClosed) await inbound.close();
  }

  List<Map<String, Object?>> get outboundMessages {
    final text = utf8.decode(outbound);
    return [
      for (final line in const LineSplitter().convert(text))
        if (line.trim().isNotEmpty)
          {
            for (final e in (jsonDecode(line) as Map).entries)
              e.key.toString(): e.value,
          },
    ];
  }
}

class _Harness {
  _Harness()
    : dispatcher = AsyncDispatcher()..start(),
      presence = AgentPresenceProjection() {
    dispatcher.registerFamily<AgentPresenceKind>(
      AgentPresenceKind.working.runtimeType,
      presence,
    );
    client = EventTransportClient(
      dispatcher: dispatcher,
      presence: presence,
      codecs: [
        AgentPresenceTransportCodec(),
        SessionLifecycleTransportCodec(),
      ],
      open: () async {
        openCount++;
        final channel = _FakeChannel();
        channels.add(channel);
        return channel;
      },
      backoff: (_) => Duration.zero,
    );
  }

  final AsyncDispatcher dispatcher;
  final AgentPresenceProjection presence;
  late final EventTransportClient client;
  var openCount = 0;
  final channels = <_FakeChannel>[];

  _FakeChannel get channel => channels.last;

  Future<void> startAndWaitSubscribe() async {
    await client.start();
    await _waitFor(
      () => channels.isNotEmpty && channel.outboundMessages.isNotEmpty,
      timeout: _timeout,
    );
  }

  void push(Map<String, Object?> object) {
    channel.inbound.add(utf8.encode(encodeTransportLine(object)));
  }

  Map<String, Object?> presenceLine(AgentPresenceEvent event) => {
    'v': eventTransportProtocolVersion,
    'type': 'event',
    'family': eventTransportFamilyAgentPresence,
    ...AgentPresenceTransportCodec().encode(event),
  };

  Future<void> dispose() async {
    await client.stop();
    await dispatcher.stop();
    await presence.close();
  }
}

AgentPresenceEvent _set({
  PresenceSeatKey seat = _seat,
  AgentPresenceKind kind = AgentPresenceKind.working,
}) => AgentPresenceEvent(
  seat: seat,
  eventKind: kind,
  timestamp: DateTime.utc(2026, 9, 12),
);

AgentPresenceEvent _clear({PresenceSeatKey seat = _seat}) => AgentPresenceEvent(
  seat: seat,
  eventKind: AgentPresenceKind.cleared,
  timestamp: DateTime.utc(2026, 9, 12),
);

void main() {
  test('start writes subscribe with presence and lifecycle families', () async {
    final h = _Harness();
    addTearDown(h.dispose);

    await h.startAndWaitSubscribe();

    final first = h.channel.outboundMessages.first;
    expect(first['type'], 'subscribe');
    expect(first['v'], eventTransportProtocolVersion);
    final families = (first['families'] as List).cast<String>();
    expect(families, contains(eventTransportFamilyAgentPresence));
    expect(families, contains(eventTransportFamilySessionLifecycle));
  });

  test('snapshot set then clear updates the projection and changes', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final seen = <PresenceSeatKey>[];
    final sub = h.presence.changes.listen(seen.add);
    addTearDown(sub.cancel);

    await h.startAndWaitSubscribe();
    h.push({
      'v': eventTransportProtocolVersion,
      'type': 'snapshotBegin',
      'family': eventTransportFamilyAgentPresence,
    });
    h.push(h.presenceLine(_set()));
    h.push({
      'v': eventTransportProtocolVersion,
      'type': 'snapshotEnd',
      'family': eventTransportFamilyAgentPresence,
    });

    await _waitFor(
      () => h.presence.availabilityFor(_seat) == AgentPresenceKind.working,
      timeout: _timeout,
    );

    seen.clear();
    h.push(h.presenceLine(_clear()));

    await _waitFor(
      () => h.presence.snapshot.isEmpty && seen.contains(_seat),
      timeout: _timeout,
    );
  });

  test('snapshotBegin clears seats present before the handshake', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    const stale = PresenceSeatKey(sessionId: 'old', memberId: 'seat');
    h.presence.handle(
      AgentPresenceEvent(
        seat: stale,
        eventKind: AgentPresenceKind.idle,
        timestamp: DateTime.utc(2026, 9, 11),
      ),
    );
    expect(h.presence.availabilityFor(stale), AgentPresenceKind.idle);

    await h.startAndWaitSubscribe();
    h.push({
      'v': eventTransportProtocolVersion,
      'type': 'snapshotBegin',
      'family': eventTransportFamilyAgentPresence,
    });
    h.push({
      'v': eventTransportProtocolVersion,
      'type': 'snapshotEnd',
      'family': eventTransportFamilyAgentPresence,
    });

    await _waitFor(
      () => h.presence.availabilityFor(stale) == null,
      timeout: _timeout,
    );
    expect(h.presence.snapshot, isEmpty);
  });

  test('v:2 lines do not dispatch and do not throw', () async {
    final h = _Harness();
    addTearDown(h.dispose);

    await h.startAndWaitSubscribe();
    h.channel.inbound.add(
      utf8.encode(
        '${jsonEncode({
          'v': 2,
          'type': 'event',
          'family': eventTransportFamilyAgentPresence,
          ...AgentPresenceTransportCodec().encode(_set()),
        })}\n',
      ),
    );
    h.push(h.presenceLine(_set(seat: const PresenceSeatKey(sessionId: 's', memberId: 'kept'))));

    const kept = PresenceSeatKey(sessionId: 's', memberId: 'kept');
    await _waitFor(
      () => h.presence.availabilityFor(kept) == AgentPresenceKind.working,
      timeout: _timeout,
    );
    expect(h.presence.availabilityFor(_seat), isNull);
  });

  test('incoming close reconnects after backoff', () async {
    final h = _Harness();
    addTearDown(h.dispose);

    await h.startAndWaitSubscribe();
    expect(h.openCount, 1);
    await h.channels.first.inbound.close();

    await _waitFor(() => h.openCount >= 2, timeout: _timeout);
  });

  test('stop does not reconnect', () async {
    final h = _Harness();
    addTearDown(h.dispose);

    await h.startAndWaitSubscribe();
    expect(h.openCount, 1);
    await h.client.stop();
    await _waitFor(() => h.channels.first.closed, timeout: _timeout);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(h.openCount, 1);
  });
}
