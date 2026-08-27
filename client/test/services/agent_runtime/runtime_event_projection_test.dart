import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/agent_runtime/runtime_event_projection.dart';
import 'package:teampilot/services/agent_runtime/seat_event_stream.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/ask_user_question_hook_gate.dart';
import 'package:teampilot/services/agent_status/exit_plan_mode_hook_gate.dart';

void main() {
  test('projection applies each seat sequence once', () async {
    final stream = SeatEventStream();
    const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');
    final applied = <int>[];
    final projection = RuntimeEventProjection(
      onEvent: (event) {
        applied.add(event.sequence);
      },
    );
    final subscription = projection.attach(stream, seat);
    addTearDown(subscription.cancel);
    addTearDown(stream.close);

    stream
      ..publish(_event(seat, 1))
      ..publish(_event(seat, 1))
      ..publish(_event(seat, 2));
    await pumpEventQueue();

    expect(applied, [1, 2]);
    expect(projection.cursorFor(seat), 2);
  });

  test(
    'attention projection derives waiting state from a published hook',
    () async {
      final stream = SeatEventStream();
      final attention = AgentAttentionCubit(pruneInterval: null);
      const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');
      final projection = AgentAttentionRuntimeEventProjection(
        attention: attention,
        resolveSkipPermissions: (_, __) => false,
      );
      final subscription = projection.attach(stream, seat);
      addTearDown(subscription.cancel);
      addTearDown(stream.close);
      addTearDown(attention.close);

      stream.publish(
        RuntimeEventEnvelope(
          seat: seat,
          cli: CliTool.codex,
          kind: RuntimeEventKind.statusReported,
          occurredAt: DateTime.utc(2026, 8, 25),
          raw: const {
            'hook_event_name': 'PermissionRequest',
            'tool_name': 'Bash',
          },
          sequence: 1,
        ),
      );
      await pumpEventQueue();

      expect(
        attention.state.attentionFor(
          sessionId: seat.sessionId,
          memberId: seat.memberId,
        ),
        AgentSeatAttention.waiting,
      );
    },
  );

  test(
    'question responder projection holds a stream event once per sequence',
    () async {
      final stream = SeatEventStream();
      final gate = AskUserQuestionHookGate();
      const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');
      final projection = AskUserQuestionRuntimeEventProjection(hookGate: gate);
      final subscription = projection.attach(stream, seat);
      addTearDown(subscription.cancel);
      addTearDown(stream.close);
      final event = RuntimeEventEnvelope(
        seat: seat,
        cli: CliTool.claude,
        kind: RuntimeEventKind.statusReported,
        occurredAt: DateTime.utc(2026, 8, 25),
        raw: const {
          'hook_event_name': 'PreToolUse',
          'tool_name': 'AskUserQuestion',
          'tool_use_id': 'ask-1',
          'tool_input': {
            'questions': [
              {
                'question': 'Continue?',
                'options': ['Yes', 'No'],
              },
            ],
          },
        },
        sequence: 1,
      );

    stream.publish(event);
    final firstResponse = projection.responseFor(event);
    stream.publish(event);
    await pumpEventQueue();
    expect(projection.responseFor(event), same(firstResponse));
      expect(
        gate.hasWaiter(
          sessionId: 'session',
          memberId: 'member',
          toolUseId: 'ask-1',
        ),
        isTrue,
      );
      expect(
        gate.complete(
          sessionId: 'session',
          memberId: 'member',
          toolUseId: 'ask-1',
          reply: const AskUserQuestionHookReply.reject(),
        ),
        isTrue,
      );
      final response = await projection.responseFor(event);
      expect(response!['hookSpecificOutput'], isA<Map>());
    },
  );

  test(
    'plan responder projection holds a stream event once per sequence',
    () async {
      final stream = SeatEventStream();
      final gate = ExitPlanModeHookGate();
      const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');
      final projection = ExitPlanModeRuntimeEventProjection(hookGate: gate);
      final subscription = projection.attach(stream, seat);
      addTearDown(subscription.cancel);
      addTearDown(stream.close);
      final event = RuntimeEventEnvelope(
        seat: seat,
        cli: CliTool.claude,
        kind: RuntimeEventKind.statusReported,
        occurredAt: DateTime.utc(2026, 8, 25),
        raw: const {
          'hook_event_name': 'PreToolUse',
          'tool_name': 'ExitPlanMode',
          'tool_use_id': 'plan-1',
          'tool_input': {'plan': '1. Ship it.'},
        },
        sequence: 1,
      );

    stream.publish(event);
    final firstResponse = projection.responseFor(event);
    stream.publish(event);
    await pumpEventQueue();
    expect(projection.responseFor(event), same(firstResponse));
      expect(
        gate.hasWaiter(
          sessionId: 'session',
          memberId: 'member',
          toolUseId: 'plan-1',
        ),
        isTrue,
      );
      expect(
        gate.complete(
          sessionId: 'session',
          memberId: 'member',
          toolUseId: 'plan-1',
          reply: const ExitPlanModeHookReply.allow(),
        ),
        isTrue,
      );
      final response = await projection.responseFor(event);
      expect(response!['hookSpecificOutput'], isA<Map>());
    },
  );
}

RuntimeEventEnvelope _event(RuntimeSeatKey seat, int sequence) =>
    RuntimeEventEnvelope(
      seat: seat,
      cli: CliTool.codex,
      kind: RuntimeEventKind.promptSubmitted,
      occurredAt: DateTime.utc(2026, 8, 25),
      sequence: sequence,
    );
