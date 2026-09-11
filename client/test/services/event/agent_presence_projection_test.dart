import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';
import 'package:teampilot/services/event/agent_presence_projection.dart';

AgentPresenceEvent _e(String session, String member, AgentPresenceKind k) =>
    AgentPresenceEvent(
      seat: PresenceSeatKey(sessionId: session, memberId: member),
      eventKind: k,
      timestamp: DateTime(2026, 9, 11),
    );

void main() {
  test('reduces the latest availability per seat, isolating seats', () async {
    final p = AgentPresenceProjection();
    p.handle(_e('s1', 'a', AgentPresenceKind.booting));
    p.handle(_e('s1', 'b', AgentPresenceKind.working));
    p.handle(_e('s1', 'a', AgentPresenceKind.idle));

    expect(
      p.availabilityFor(const PresenceSeatKey(sessionId: 's1', memberId: 'a')),
      AgentPresenceKind.idle,
    );
    expect(
      p.availabilityFor(const PresenceSeatKey(sessionId: 's1', memberId: 'b')),
      AgentPresenceKind.working,
    );
    expect(
      p.availabilityFor(const PresenceSeatKey(sessionId: 's2', memberId: 'a')),
      isNull,
    );
    await p.close();
  });

  test('repeated identical events are idempotent and do not re-broadcast', () async {
    final p = AgentPresenceProjection();
    final seen = <PresenceSeatKey>[];
    final sub = p.changes.listen(seen.add);

    p.handle(_e('s', 'm', AgentPresenceKind.working));
    p.handle(_e('s', 'm', AgentPresenceKind.working));
    await Future<void>.delayed(Duration.zero);

    expect(seen.length, 1, reason: 'unchanged value must not re-notify');
    await sub.cancel();
    await p.close();
  });

  test('removeSeat clears the entry', () async {
    final p = AgentPresenceProjection();
    const seat = PresenceSeatKey(sessionId: 's', memberId: 'm');
    p.handle(_e('s', 'm', AgentPresenceKind.working));
    p.removeSeat(seat);
    expect(p.availabilityFor(seat), isNull);
    p.removeSeat(seat); // idempotent
    await p.close();
  });
}
