import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/async_dispatcher.dart';
import 'package:teampilot/services/event/dispatcher.dart';
import 'package:teampilot/services/event/event_publisher.dart';
import 'package:teampilot/services/event/session_lifecycle_event.dart';

void main() {
  test(
    'EventPublisher dispatches lifecycle events through the dispatcher',
    () async {
      final d = AsyncDispatcher()..start();
      final publisher = EventPublisher()..attach(d);
      final received = <SessionLifecycleEvent>[];
      d.registerFamily<SessionLifecycleKind>(
        SessionLifecycleKind.sessionStarted.runtimeType,
        _Recorder(received),
      );

      publisher.dispatchSessionLifecycle(
        SessionLifecycleEvent.sessionStarted(
          sessionId: 's-1',
          workspaceId: 'w-1',
          timestamp: DateTime(2026),
        ),
      );
      await d.stop();

      expect(received.single.kind, SessionLifecycleKind.sessionStarted);
      expect(received.single.sessionId, 's-1');
    },
  );

  test('attachedDispatcher reflects attach state', () {
    final publisher = EventPublisher();
    expect(publisher.attachedDispatcher, isNull);
    final d = AsyncDispatcher();
    publisher.attach(d);
    expect(publisher.attachedDispatcher, same(d));
  });

  test('unattached publisher is a no-op', () {
    final publisher = EventPublisher();
    // Must not throw.
    publisher.dispatchSessionLifecycle(
      SessionLifecycleEvent.sessionClosed(
        sessionId: 's-2',
        workspaceId: 'w-1',
        timestamp: DateTime(2026),
      ),
    );
  });

  test('seat events carry a required memberId; session events do not', () {
    final seat = SessionLifecycleEvent.seatStarted(
      sessionId: 's-1',
      workspaceId: 'w-1',
      memberId: 'm-1',
      timestamp: DateTime(2026),
    );
    expect(seat.memberId, 'm-1');
    expect(seat.kind, SessionLifecycleKind.seatStarted);

    final session = SessionLifecycleEvent.sessionSpawned(
      sessionId: 's-1',
      workspaceId: 'w-1',
      timestamp: DateTime(2026),
    );
    expect(session.memberId, isNull);
    expect(session.kind, SessionLifecycleKind.sessionSpawned);
  });
}

class _Recorder implements EventHandler<SessionLifecycleEvent> {
  _Recorder(this.events);

  final List<SessionLifecycleEvent> events;

  @override
  void handle(SessionLifecycleEvent event) => events.add(event);
}
