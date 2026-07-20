import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';

void main() {
  group('AgentAttentionCubit', () {
    test('setSeatState waiting then sessionHasWaiting', () {
      final c = AgentAttentionCubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      expect(
        c.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.waiting,
      );
      expect(c.state.sessionHasWaiting('s1'), isTrue);
    });

    test('skipPermissions suppresses waiting UI state', () {
      final c = AgentAttentionCubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: true,
      );
      expect(c.state.attentionFor(sessionId: 's1', memberId: 'm1'), isNull);
      expect(c.state.sessionHasWaiting('s1'), isFalse);
    });

    test('skipPermissions keeps prior non-waiting state', () {
      final c = AgentAttentionCubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.working),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: true,
      );
      expect(
        c.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.working,
      );
      expect(c.state.sessionHasWaiting('s1'), isFalse);
    });

    test('clearSeat removes entry', () {
      final c = AgentAttentionCubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      c.clearSeat(sessionId: 's1', memberId: 'm1');
      expect(c.state.attentionFor(sessionId: 's1', memberId: 'm1'), isNull);
      expect(c.state.sessionHasWaiting('s1'), isFalse);
    });

    test('done clears waiting', () {
      final c = AgentAttentionCubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.done),
        skipPermissions: false,
      );
      expect(
        c.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.done,
      );
      expect(c.state.sessionHasWaiting('s1'), isFalse);
    });

    test('multi-seat waitingMemberIds', () {
      final c = AgentAttentionCubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm2',
        event: const AgentStatusEvent(state: AgentSeatAttention.working),
        skipPermissions: false,
      );
      expect(c.state.sessionHasWaiting('s1'), isTrue);
      expect(c.state.waitingMemberIds('s1'), ['m1']);
    });

    test('clearSession removes all seats for session', () {
      final c = AgentAttentionCubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm2',
        event: const AgentStatusEvent(state: AgentSeatAttention.working),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's2',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      c.clearSession('s1');
      expect(c.state.attentionFor(sessionId: 's1', memberId: 'm1'), isNull);
      expect(c.state.attentionFor(sessionId: 's1', memberId: 'm2'), isNull);
      expect(
        c.state.attentionFor(sessionId: 's2', memberId: 'm1'),
        AgentSeatAttention.waiting,
      );
    });

    test('stale entries older than 30m are dropped', () {
      var now = DateTime.utc(2026, 7, 19, 12);
      final c = AgentAttentionCubit(clock: () => now);
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      now = now.add(const Duration(minutes: 31));
      expect(c.state.sessionHasWaiting('s1'), isFalse);
    });
  });
}
