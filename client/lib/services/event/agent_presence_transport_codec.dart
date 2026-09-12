import 'agent_presence_event.dart';
import 'dispatcher.dart';
import 'event_transport_codec.dart';

final class AgentPresenceTransportCodec implements EventTransportFamilyCodec {
  @override
  String get family => eventTransportFamilyAgentPresence;

  @override
  Map<String, Object?> encode(DispatcherEvent event) {
    final e = event as AgentPresenceEvent;
    return {
      'op': e.eventKind == AgentPresenceKind.cleared ? 'clear' : 'set',
      'seat': {'sessionId': e.sessionId, 'memberId': e.memberId},
      if (e.eventKind != AgentPresenceKind.cleared) 'kind': e.eventKind.name,
      'ts': e.timestamp.toUtc().toIso8601String(),
    };
  }

  @override
  DispatcherEvent? decode(Map<String, Object?> payload) {
    final seatRaw = payload['seat'];
    if (seatRaw is! Map) return null;
    final sessionId = seatRaw['sessionId'] as String?;
    final memberId = seatRaw['memberId'] as String?;
    if (sessionId == null || memberId == null) return null;
    final ts = DateTime.tryParse(payload['ts'] as String? ?? '');
    if (ts == null) return null;
    final op = payload['op'] as String?;
    final AgentPresenceKind kind;
    if (op == 'clear') {
      kind = AgentPresenceKind.cleared;
    } else if (op == 'set') {
      final parsed = switch (payload['kind'] as String?) {
        'booting' => AgentPresenceKind.booting,
        'working' => AgentPresenceKind.working,
        'idle' => AgentPresenceKind.idle,
        _ => null,
      };
      if (parsed == null) return null;
      kind = parsed;
    } else {
      return null;
    }
    return AgentPresenceEvent(
      seat: PresenceSeatKey(sessionId: sessionId, memberId: memberId),
      eventKind: kind,
      timestamp: ts.toUtc(),
    );
  }
}
