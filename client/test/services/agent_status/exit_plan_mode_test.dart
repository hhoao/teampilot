import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/agent_status/exit_plan_mode.dart';

void main() {
  test('preserves plan payload and toolUseId across a later waiting hook',
      () {
    const previous = AgentStatusEvent(
      state: AgentSeatAttention.waiting,
      toolName: 'ExitPlanMode',
      toolUseId: 'toolu-plan-1',
      planText: '1. Do x.',
      planFilePath: '/tmp/plan.md',
    );
    const next = AgentStatusEvent(state: AgentSeatAttention.waiting);
    final effective = preserveExitPlanModePayload(previous, next);
    expect(effective.planText, '1. Do x.');
    expect(effective.planFilePath, '/tmp/plan.md');
    expect(effective.toolUseId, 'toolu-plan-1');
  });

  test('does not preserve across a non-waiting event', () {
    const previous = AgentStatusEvent(
      state: AgentSeatAttention.waiting,
      toolName: 'ExitPlanMode',
      toolUseId: 'toolu-plan-2',
      planText: '1. Do x.',
    );
    const next = AgentStatusEvent(
      state: AgentSeatAttention.working,
      toolName: 'PostToolUse',
    );
    final effective = preserveExitPlanModePayload(previous, next);
    expect(effective.planText, isNull);
    expect(effective.toolUseId, isNull);
  });
}
