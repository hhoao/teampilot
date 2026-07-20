import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat/session_launch_host.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/agent_status/agent_status_seat_lookup.dart';

void main() {
  // SessionLaunchPipeline._restartTeamSession needs a full host fake; the
  // restart path calls clearAgentStatusSession → clearAgentStatusSessionSeats.
  group('clearAgentStatusSessionSeats', () {
    test('clears attention and seat lookup for session, keeps other sessions', () {
      final attention = AgentAttentionCubit(pruneInterval: null);
      addTearDown(attention.close);
      final seats = AgentStatusSeatLookup();

      attention.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      attention.applyEvent(
        sessionId: 's2',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      seats.registerSeat(
        sessionId: 's1',
        memberId: 'm1',
        cli: CliTool.claude,
        skipPermissions: false,
      );
      seats.registerSeat(
        sessionId: 's2',
        memberId: 'm1',
        cli: CliTool.codex,
        skipPermissions: false,
      );

      clearAgentStatusSessionSeats(
        attention: attention,
        seatLookup: seats,
        sessionId: 's1',
      );

      expect(attention.state.attentionFor(sessionId: 's1', memberId: 'm1'), isNull);
      expect(
        attention.state.attentionFor(sessionId: 's2', memberId: 'm1'),
        AgentSeatAttention.waiting,
      );
      expect(seats.resolveCli('s1', 'm1'), isNull);
      expect(seats.resolveCli('s2', 'm1'), CliTool.codex);
    });
  });
}
