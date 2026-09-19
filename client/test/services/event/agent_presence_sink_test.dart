import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';
import 'package:teampilot/services/event/agent_presence_sink.dart';
import 'package:teampilot/services/event/async_dispatcher.dart';
import 'package:teampilot/services/event/dispatcher.dart';

class _Recorder implements EventHandler<AgentPresenceEvent> {
  final events = <AgentPresenceEvent>[];
  @override
  void handle(AgentPresenceEvent event) => events.add(event);
}

void main() {
  test('dispatcher-backed sink delivers to a registered handler', () async {
    final d = AsyncDispatcher()..start();
    final sink = DispatcherAgentPresenceSink(d);
    final rec = _Recorder();
    d.registerFamily<AgentPresenceKind>(
      AgentPresenceKind.working.runtimeType,
      rec,
    );

    sink.publish(
      AgentPresenceEvent(
        seat: const PresenceSeatKey(sessionId: 's', memberId: 'm'),
        eventKind: AgentPresenceKind.working,
        timestamp: DateTime(2026, 9, 11),
      ),
    );
    await d.stop();

    expect(rec.events.single.memberId, 'm');
  });

  test('noop sink accepts publishes without side effects', () {
    const sink = NoopAgentPresenceSink();
    sink.publish(
      AgentPresenceEvent(
        seat: const PresenceSeatKey(sessionId: 's', memberId: 'm'),
        eventKind: AgentPresenceKind.idle,
        timestamp: DateTime(2026, 9, 11),
      ),
    );
  });
}
