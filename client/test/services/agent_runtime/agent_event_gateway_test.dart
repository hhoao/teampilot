import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/agent_event_gateway.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/agent_runtime/runtime_event_journal.dart';
import 'package:teampilot/services/agent_runtime/seat_event_stream.dart';
import 'package:teampilot/services/agent_status/ask_user_question_hook_gate.dart';
import 'package:teampilot/services/agent_status/exit_plan_mode_hook_gate.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test(
    'gateway journals before publishing and ignores a duplicate native event id',
    () async {
      final journal = MemoryRuntimeEventJournal();
      final stream = SeatEventStream();
      const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');
      final published = <RuntimeEventEnvelope>[];
      final subscription = stream.eventsFor(seat).listen(published.add);
      addTearDown(subscription.cancel);
      addTearDown(stream.close);

      final gateway = AgentEventGateway(
        journal: journal,
        stream: stream,
        registry: CliToolRegistry.builtIn(),
        resolveCli: (_, __) => CliTool.codex,
        clock: () => DateTime.utc(2026, 8, 25),
      );

      await gateway.handleJson(seat, {
        'id': 'native-1',
        'hook_event_name': 'UserPromptSubmit',
        'prompt': 'x',
      });
      await gateway.handleJson(seat, {
        'id': 'native-1',
        'hook_event_name': 'UserPromptSubmit',
        'prompt': 'x',
      });

      expect(await journal.replay(seat).toList(), hasLength(1));
      expect(published.single.kind, RuntimeEventKind.promptSubmitted);
    },
  );

  test(
    'gateway restores native event ids from the journal before accepting hooks',
    () async {
      final journal = MemoryRuntimeEventJournal();
      const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');
      final first = AgentEventGateway(
        journal: journal,
        stream: SeatEventStream(),
        registry: CliToolRegistry.builtIn(),
        resolveCli: (_, __) => CliTool.codex,
        clock: () => DateTime.utc(2026, 8, 25),
      );
      await first.handleJson(seat, {
        'id': 'native-1',
        'hook_event_name': 'UserPromptSubmit',
        'prompt': 'x',
      });

      final restarted = AgentEventGateway(
        journal: journal,
        stream: SeatEventStream(),
        registry: CliToolRegistry.builtIn(),
        resolveCli: (_, __) => CliTool.codex,
        clock: () => DateTime.utc(2026, 8, 25),
      );
      await restarted.handleJson(seat, {
        'id': 'native-1',
        'hook_event_name': 'UserPromptSubmit',
        'prompt': 'x',
      });

      expect(await journal.replay(seat).toList(), hasLength(1));
    },
  );

  test('held hook replies retain their native response payloads', () {
    expect(const AskUserQuestionHookReply.reject().toHookResponse(), {
      'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': 'User dismissed the question',
      },
    });
    expect(const ExitPlanModeHookReply.allow().toHookResponse(), {
      'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'allow',
      },
    });
  });
}
