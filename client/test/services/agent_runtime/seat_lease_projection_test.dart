import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/seat_lease_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/agent_runtime/seat_lease_projection.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart'
    show agentSeatKey;

RuntimeEventEnvelope _envelope(
  Map<String, Object?> raw, {
  RuntimeEventKind kind = RuntimeEventKind.statusReported,
  int sequence = 1,
}) =>
    RuntimeEventEnvelope(
      seat: const RuntimeSeatKey(sessionId: 's1', memberId: 'm1'),
      cli: CliTool.claude,
      kind: kind,
      occurredAt: DateTime(2026, 1, 1),
      sequence: sequence,
      raw: raw,
    );

void main() {
  group('seatLeaseProjection', () {
    test('PreToolUse background Bash acquires a lease keyed by tool_use_id',
        () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      final projection = seatLeaseProjection(leases: cubit);

      projection.apply(_envelope({
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Bash',
        'tool_input': {'command': 'x', 'run_in_background': true},
        'tool_use_id': 'call_1',
      }));

      expect(cubit.state.seatHasLeases(sessionId: 's1', memberId: 'm1'), isTrue);
      final seatKey = agentSeatKey(sessionId: 's1', memberId: 'm1');
      expect(cubit.state.leases.keys, contains(seatKey));
      expect(cubit.state.leases[seatKey]?.keys, ['call_1']);
    });

    test('task-notification UserPromptSubmit releases the matching lease',
        () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      final projection = seatLeaseProjection(leases: cubit);
      projection.apply(_envelope({
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Bash',
        'tool_input': {'command': 'x', 'run_in_background': true},
        'tool_use_id': 'call_1',
      }, sequence: 1));

      projection.apply(_envelope({
        'hook_event_name': 'UserPromptSubmit',
        'prompt': '<task-notification>\n'
            '<task-id>t1</task-id>\n'
            '<tool-use-id>call_1</tool-use-id>\n'
            '<status>completed</status>\n'
            '</task-notification>',
      }, sequence: 2));

      expect(cubit.state.seatHasLeases(sessionId: 's1', memberId: 'm1'), isFalse);
    });

    test('real user prompt does not release', () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      final projection = seatLeaseProjection(leases: cubit);
      projection.apply(_envelope({
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Bash',
        'tool_input': {'command': 'x', 'run_in_background': true},
        'tool_use_id': 'call_1',
      }, sequence: 1));

      projection.apply(_envelope({
        'hook_event_name': 'UserPromptSubmit',
        'prompt': 'status update?',
      }, sequence: 2));

      expect(cubit.state.seatHasLeases(sessionId: 's1', memberId: 'm1'), isTrue);
    });

    test('notification for an unknown lease is a no-op', () {
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      final projection = seatLeaseProjection(leases: cubit);
      projection.apply(_envelope({
        'hook_event_name': 'UserPromptSubmit',
        'prompt': '<task-notification>\n'
            '<task-id>t</task-id>\n'
            '<tool-use-id>ghost</tool-use-id>\n'
            '<status>completed</status>\n'
            '</task-notification>',
      }));
      expect(cubit.state.leases, isEmpty);
    });

    test('seatIdle does not clear leases', () {
      // A member reporting idle at turn end is exactly when a background
      // task is still running — leases must survive /idle. They clear on
      // the paired notification, TTL, or seat teardown only.
      final cubit = SeatLeaseCubit(pruneInterval: null);
      addTearDown(cubit.close);
      final projection = seatLeaseProjection(leases: cubit);
      projection.apply(_envelope({
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Bash',
        'tool_input': {'command': 'x', 'run_in_background': true},
        'tool_use_id': 'call_1',
      }, sequence: 1));

      final idle = RuntimeEventEnvelope(
        seat: const RuntimeSeatKey(sessionId: 's1', memberId: 'm1'),
        cli: CliTool.claude,
        kind: RuntimeEventKind.seatIdle,
        occurredAt: DateTime(2026, 1, 1),
        sequence: 2,
      );
      projection.apply(idle);

      expect(cubit.state.seatHasLeases(sessionId: 's1', memberId: 'm1'), isTrue);
    });
  });
}
