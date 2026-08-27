import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/agent_runtime/seat_event_stream.dart';

void main() {
  test('publishes only matching seat events in sequence order', () async {
    final stream = SeatEventStream();
    const target = RuntimeSeatKey(sessionId: 'session', memberId: 'a');
    final sequences = <int>[];
    final subscription = stream.eventsFor(target).listen(
      (event) => sequences.add(event.sequence),
    );

    stream.publish(_event(memberId: 'b', sequence: 1));
    stream.publish(_event(memberId: 'a', sequence: 1));
    stream.publish(_event(memberId: 'a', sequence: 2));
    await pumpEventQueue();

    expect(sequences, [1, 2]);
    await subscription.cancel();
    await stream.close();
  });
}

RuntimeEventEnvelope _event({required String memberId, required int sequence}) =>
    RuntimeEventEnvelope(
      seat: RuntimeSeatKey(sessionId: 'session', memberId: memberId),
      cli: CliTool.codex,
      kind: RuntimeEventKind.promptSubmitted,
      occurredAt: DateTime.utc(2026),
      sequence: sequence,
    );
