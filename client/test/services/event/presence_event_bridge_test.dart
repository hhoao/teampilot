import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';
import 'package:teampilot/services/event/agent_presence_sink.dart';
import 'package:teampilot/services/event/presence_event_bridge.dart';

class _SpySink implements AgentPresenceSink {
  final events = <AgentPresenceEvent>[];
  @override
  void publish(AgentPresenceEvent event) => events.add(event);
}

void main() {
  const seat = PresenceSeatKey(sessionId: 's', memberId: 'm');

  test('publishes on first report and on every change, deduping repeats', () {
    final sink = _SpySink();
    final bridge = PresenceEventBridge(
      sink: sink,
      clock: () => DateTime(2026, 9, 11),
    );

    bridge.reportAvailability(seat, AgentPresenceKind.booting);
    bridge.reportAvailability(seat, AgentPresenceKind.booting); // repeat
    bridge.reportAvailability(seat, AgentPresenceKind.working);
    bridge.reportAvailability(seat, AgentPresenceKind.idle);

    expect(sink.events.map((e) => e.eventKind), [
      AgentPresenceKind.booting,
      AgentPresenceKind.working,
      AgentPresenceKind.idle,
    ]);
    expect(sink.events.first.seat, seat);
  });

  test('null report publishes cleared and clears the baseline', () {
    final sink = _SpySink();
    final bridge = PresenceEventBridge(
      sink: sink,
      clock: () => DateTime(2026, 9, 12),
    );
    bridge.reportAvailability(seat, AgentPresenceKind.working);
    bridge.reportAvailability(seat, null);
    expect(sink.events.map((e) => e.eventKind), [
      AgentPresenceKind.working,
      AgentPresenceKind.cleared,
    ]);
    expect(sink.events.last.timestamp, DateTime(2026, 9, 12));

    bridge.reportAvailability(seat, AgentPresenceKind.working);
    expect(sink.events.map((e) => e.eventKind), [
      AgentPresenceKind.working,
      AgentPresenceKind.cleared,
      AgentPresenceKind.working,
    ]);
  });

  test('forget clears baseline', () {
    final sink = _SpySink();
    final bridge = PresenceEventBridge(sink: sink);
    bridge.reportAvailability(seat, AgentPresenceKind.idle);
    bridge.forget(seat);
    bridge.reportAvailability(seat, AgentPresenceKind.idle);
    expect(sink.events.length, 2);
  });

  test('dispose stops publishing', () {
    final sink = _SpySink();
    final bridge = PresenceEventBridge(sink: sink);
    bridge.dispose();
    bridge.reportAvailability(seat, AgentPresenceKind.idle);
    expect(sink.events, isEmpty);
  });

  test('seats are isolated', () {
    final sink = _SpySink();
    final bridge = PresenceEventBridge(sink: sink);
    bridge.reportAvailability(
      const PresenceSeatKey(sessionId: 's', memberId: 'a'),
      AgentPresenceKind.working,
    );
    bridge.reportAvailability(
      const PresenceSeatKey(sessionId: 's', memberId: 'b'),
      AgentPresenceKind.working,
    );
    expect(sink.events.length, 2);
  });
}
