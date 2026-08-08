import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';

void main() {
  test('clearWorkingIfWorking removes a working seat', () {
    final cubit = AgentAttentionCubit(pruneInterval: null);
    cubit.applyEvent(
      sessionId: 's1',
      memberId: 'm1',
      event: const AgentStatusEvent(state: AgentSeatAttention.working),
      skipPermissions: false,
    );
    cubit.clearWorkingIfWorking(sessionId: 's1', memberId: 'm1');
    expect(
      cubit.state.attentionFor(sessionId: 's1', memberId: 'm1'),
      isNull,
    );
  });

  test('clearWorkingIfWorking does NOT remove a waiting seat', () {
    final cubit = AgentAttentionCubit(pruneInterval: null);
    cubit.applyEvent(
      sessionId: 's1',
      memberId: 'm1',
      event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
      skipPermissions: false,
    );
    cubit.clearWorkingIfWorking(sessionId: 's1', memberId: 'm1');
    expect(
      cubit.state.attentionFor(sessionId: 's1', memberId: 'm1'),
      AgentSeatAttention.waiting,
    );
  });

  test('clearWorkingIfWorking is a no-op when seat absent', () {
    final cubit = AgentAttentionCubit(pruneInterval: null);
    cubit.clearWorkingIfWorking(sessionId: 's1', memberId: 'm1'); // no throw
    expect(cubit.state.seats, isEmpty);
  });
}
