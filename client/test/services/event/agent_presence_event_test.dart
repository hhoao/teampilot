import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';

void main() {
  test('carries seat identity through the event', () {
    final e = AgentPresenceEvent(
      seat: const PresenceSeatKey(sessionId: 's-1', memberId: 'dev'),
      eventKind: AgentPresenceKind.working,
      timestamp: DateTime(2026, 9, 11),
    );
    expect(e.eventKind, AgentPresenceKind.working);
    expect(e.sessionId, 's-1');
    expect(e.memberId, 'dev');
    expect(e.timestamp, DateTime(2026, 9, 11));
  });

  test('seat key has value equality', () {
    const a = PresenceSeatKey(sessionId: 's', memberId: 'm');
    const b = PresenceSeatKey(sessionId: 's', memberId: 'm');
    const c = PresenceSeatKey(sessionId: 's', memberId: 'other');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });

  test('seat key toString names both identity halves', () {
    const key = PresenceSeatKey(sessionId: 's', memberId: 'm');
    expect(key.toString(), 'PresenceSeatKey(s/m)');
  });
}
