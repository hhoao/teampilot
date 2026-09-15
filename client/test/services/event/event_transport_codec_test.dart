// client/test/services/event/event_transport_codec_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';
import 'package:teampilot/services/event/agent_presence_transport_codec.dart';
import 'package:teampilot/services/event/event_transport_codec.dart';
import 'package:teampilot/services/event/session_lifecycle_event.dart';
import 'package:teampilot/services/event/session_lifecycle_transport_codec.dart';

void main() {
  test('round-trips a presence set line', () {
    final codec = AgentPresenceTransportCodec();
    final event = AgentPresenceEvent(
      seat: const PresenceSeatKey(sessionId: 's', memberId: 'dev'),
      eventKind: AgentPresenceKind.working,
      timestamp: DateTime.utc(2026, 9, 12),
    );
    final payload = codec.encode(event);
    expect(payload['op'], 'set');
    expect(payload['kind'], 'working');
    final line = encodeTransportLine({
      'v': eventTransportProtocolVersion,
      'type': 'event',
      'family': codec.family,
      ...payload,
    });
    expect(line.endsWith('\n'), isTrue);
    expect(
      line.contains('\n', 0) && line.indexOf('\n') == line.length - 1,
      isTrue,
    );
    final decoded = tryDecodeTransportLine(line);
    expect(decoded, isNotNull);
    final back = codec.decode(decoded!) as AgentPresenceEvent;
    expect(back.seat, event.seat);
    expect(back.eventKind, AgentPresenceKind.working);
  });

  test('round-trips a presence clear line', () {
    final codec = AgentPresenceTransportCodec();
    final event = AgentPresenceEvent(
      seat: const PresenceSeatKey(sessionId: 's', memberId: 'dev'),
      eventKind: AgentPresenceKind.cleared,
      timestamp: DateTime.utc(2026, 9, 12),
    );
    final payload = codec.encode(event);
    expect(payload['op'], 'clear');
    expect(payload.containsKey('kind'), isFalse);
    final back = codec.decode(payload) as AgentPresenceEvent;
    expect(back.eventKind, AgentPresenceKind.cleared);
  });

  test('round-trips a sessionLifecycle started line', () {
    final codec = SessionLifecycleTransportCodec();
    final event = SessionLifecycleEvent.sessionStarted(
      sessionId: 's',
      workspaceId: 'ws',
      timestamp: DateTime.utc(2026, 9, 12),
    );
    final back = codec.decode(codec.encode(event)) as SessionLifecycleEvent;
    expect(back.eventKind, SessionLifecycleKind.sessionStarted);
    expect(back.sessionId, 's');
    expect(back.workspaceId, 'ws');
    expect(back.memberId, isNull);
  });

  test('drops v!=1 and malformed json', () {
    expect(tryDecodeTransportLine('{"v":2,"type":"event"}\n'), isNull);
    expect(tryDecodeTransportLine('not-json\n'), isNull);
  });

  test('oversize is detected at 65536 bytes', () {
    expect(transportLineTooLong(List.filled(65536, 10)), isFalse);
    expect(transportLineTooLong(List.filled(65537, 10)), isTrue);
  });

  test('unknown presence kind decode returns null', () {
    final codec = AgentPresenceTransportCodec();
    expect(
      codec.decode({
        'op': 'set',
        'kind': 'nope',
        'seat': {'sessionId': 's', 'memberId': 'm'},
        'ts': '2026-09-12T00:00:00.000Z',
      }),
      isNull,
    );
  });
}
