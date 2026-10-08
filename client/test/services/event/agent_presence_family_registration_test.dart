import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';
import 'package:teampilot/services/event/agent_presence_projection.dart';
import 'package:teampilot/services/event/agent_presence_sink.dart';
import 'package:teampilot/services/event/async_dispatcher.dart';

void main() {
  // The app shell registers the projection with a single
  // `registerFamily<AgentPresenceKind>(AgentPresenceKind.working.runtimeType, p)`
  // call. Routing keys on `event.eventKind.runtimeType` (the family kind enum
  // Type), and every value of an enum shares its runtimeType, so one
  // registration must carry booting / working / idle alike. This drives all
  // three through a real AsyncDispatcher to pin that contract.
  test(
    'one family registration carries all three kinds to the projection',
    () async {
      final d = AsyncDispatcher()..start();
      final projection = AgentPresenceProjection();
      d.registerFamily<AgentPresenceKind>(
        // Registered via one member's runtimeType, exactly as app_shell does.
        AgentPresenceKind.working.runtimeType,
        projection,
      );
      final sink = DispatcherAgentPresenceSink(d);

      const booting = PresenceSeatKey(sessionId: 's', memberId: 'boot');
      const working = PresenceSeatKey(sessionId: 's', memberId: 'work');
      const idle = PresenceSeatKey(sessionId: 's', memberId: 'idle');
      const cases = <(PresenceSeatKey, AgentPresenceKind)>[
        (booting, AgentPresenceKind.booting),
        (working, AgentPresenceKind.working),
        (idle, AgentPresenceKind.idle),
      ];
      for (final (seat, kind) in cases) {
        sink.publish(
          AgentPresenceEvent(
            seat: seat,
            eventKind: kind,
            timestamp: DateTime(2026, 9, 11),
          ),
        );
      }
      await d.stop();

      expect(projection.availabilityFor(booting), AgentPresenceKind.booting);
      expect(projection.availabilityFor(working), AgentPresenceKind.working);
      expect(projection.availabilityFor(idle), AgentPresenceKind.idle);
      expect(projection.snapshot.length, 3);
      await projection.close();
    },
  );

  // The dispatcher keys its handler map on the same runtimeType, so the three
  // values must collapse to a single family key — no per-value registration is
  // possible or needed.
  test('the three kinds share one runtimeType family key', () {
    expect(
      AgentPresenceKind.booting.runtimeType,
      AgentPresenceKind.working.runtimeType,
    );
    expect(
      AgentPresenceKind.idle.runtimeType,
      AgentPresenceKind.working.runtimeType,
    );
  });

  test(
    'cleared shares the family runtimeType so one registration covers it',
    () {
      expect(
        AgentPresenceKind.cleared.runtimeType,
        AgentPresenceKind.working.runtimeType,
      );
    },
  );
}
