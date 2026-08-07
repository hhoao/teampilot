import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/agent_status/ask_user_question.dart';

AgentAttentionCubit _cubit({DateTime Function()? clock}) {
  final c = AgentAttentionCubit(clock: clock, pruneInterval: null);
  addTearDown(c.close);
  return c;
}

void main() {
  group('AgentAttentionCubit', () {
    test('setSeatState waiting then sessionHasWaiting', () {
      final c = _cubit();
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
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: true,
      );
      expect(c.state.attentionFor(sessionId: 's1', memberId: 'm1'), isNull);
      expect(c.state.sessionHasWaiting('s1'), isFalse);
    });

    test('skipPermissions suppresses PermissionRequest waiting', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PermissionRequest',
          toolName: 'Bash',
        ),
        skipPermissions: true,
      );
      expect(c.state.attentionFor(sessionId: 's1', memberId: 'm1'), isNull);
      expect(c.state.sessionHasWaiting('s1'), isFalse);
    });

    test('skipPermissions keeps AskUserQuestion waiting (not skipped by CLI)',
        () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PreToolUse',
          toolName: 'AskUserQuestion',
        ),
        skipPermissions: true,
      );
      expect(
        c.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.waiting,
      );
      expect(c.state.sessionHasWaiting('s1'), isTrue);
    });

    test('skipPermissions keeps ExitPlanMode waiting (plan approval needed)',
        () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PermissionRequest',
          toolName: 'ExitPlanMode',
        ),
        skipPermissions: true,
      );
      expect(
        c.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.waiting,
      );
      expect(c.state.sessionHasWaiting('s1'), isTrue);
    });

    test('PermissionRequest keeps ExitPlanMode plan payload from PreToolUse',
        () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PreToolUse',
          toolName: 'ExitPlanMode',
          planText: 'Refactor the launcher.',
          planFilePath: '/tmp/plan.md',
        ),
        skipPermissions: true,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PermissionRequest',
          toolName: 'ExitPlanMode',
        ),
        skipPermissions: true,
      );
      final entry = c.state.entryFor(sessionId: 's1', memberId: 'm1');
      expect(entry?.attention, AgentSeatAttention.waiting);
      expect(entry?.lastEvent?.planText, 'Refactor the launcher.');
      expect(entry?.lastEvent?.planFilePath, '/tmp/plan.md');
    });

    test('skipPermissions keeps opencode question.asked waiting', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'question.asked',
        ),
        skipPermissions: true,
      );
      expect(
        c.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.waiting,
      );
      expect(c.state.sessionHasWaiting('s1'), isTrue);
    });

    test('skipPermissions keeps prior non-waiting state', () {
      final c = _cubit();
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
      final c = _cubit();
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
      final c = _cubit();
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
      final c = _cubit();
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
      final c = _cubit();
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
      final c = _cubit(clock: () => now);
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      now = now.add(const Duration(minutes: 31));
      expect(c.state.sessionHasWaiting('s1'), isFalse);
    });

    test('pruneStale emits and removes stale seats from the map', () {
      var now = DateTime.utc(2026, 7, 19, 12);
      final c = _cubit(clock: () => now);
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      final key = agentSeatKey(sessionId: 's1', memberId: 'm1');
      expect(c.state.seats.containsKey(key), isTrue);

      now = now.add(const Duration(minutes: 31));
      // Soft filter alone: map still holds the entry until prune emits.
      expect(c.state.seats.containsKey(key), isTrue);

      c.pruneStale();
      expect(c.state.sessionHasWaiting('s1'), isFalse);
      expect(c.state.seats.containsKey(key), isFalse);
    });

    test('sticky: other-subagent PreToolUse does not clear waiting', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PermissionRequest',
          toolName: 'Bash',
          toolInput: 'rm -rf /tmp/x',
          toolAgentId: 'agent-a',
        ),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.working,
          hookEventName: 'PreToolUse',
          toolName: 'Read',
          toolInput: '/tmp/other.txt',
          toolUseId: 'toolu-other',
          toolAgentId: 'agent-b',
        ),
        skipPermissions: false,
      );
      expect(
        c.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.waiting,
      );
    });

    test('sticky: matching agent_id PreToolUse clears waiting', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PermissionRequest',
          toolName: 'Bash',
          toolInput: 'pnpm test',
          toolAgentId: 'agent-a',
          toolAgentType: 'Review',
        ),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.working,
          hookEventName: 'PreToolUse',
          toolName: 'Bash',
          toolInput: 'pnpm test',
          toolUseId: 'toolu-approved',
          toolAgentId: 'agent-a',
          toolAgentType: 'Review',
        ),
        skipPermissions: false,
      );
      expect(
        c.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.working,
      );
    });

    test('sticky: inherits tool_use_id then PostToolUse clears', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.working,
          hookEventName: 'PreToolUse',
          toolName: 'Bash',
          toolInput: 'echo hi',
          toolUseId: 'toolu-1',
        ),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PermissionRequest',
          toolName: 'Bash',
          toolInput: 'echo hi',
        ),
        skipPermissions: false,
      );
      expect(
        c.state.seats[agentSeatKey(sessionId: 's1', memberId: 'm1')]
            ?.lastEvent
            ?.toolUseId,
        'toolu-1',
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.working,
          hookEventName: 'PostToolUse',
          toolName: 'Bash',
          toolInput: 'echo hi',
          toolUseId: 'toolu-1',
        ),
        skipPermissions: false,
      );
      expect(
        c.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.working,
      );
    });

    test('synthetic working (no hook) clears waiting', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PermissionRequest',
          toolName: 'Bash',
        ),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.working),
        skipPermissions: false,
      );
      expect(
        c.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.working,
      );
    });

    test('sessionIsAgentActive for waiting and working, not done', () {
      final c = _cubit();
      expect(c.state.sessionIsAgentActive('s1'), isFalse);
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      expect(c.state.sessionIsAgentActive('s1'), isTrue);
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.working),
        skipPermissions: false,
      );
      expect(c.state.sessionIsAgentActive('s1'), isTrue);
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.done),
        skipPermissions: false,
      );
      expect(c.state.sessionIsAgentActive('s1'), isFalse);
    });

    test('sessionIsAgentActive can ignore parked members', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'parked',
        event: const AgentStatusEvent(state: AgentSeatAttention.working),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'busy',
        event: const AgentStatusEvent(state: AgentSeatAttention.working),
        skipPermissions: false,
      );
      expect(
        c.state.sessionIsAgentActive(
          's1',
          includeMember: (id) => id != 'parked',
        ),
        isTrue,
      );
      expect(
        c.state.sessionIsAgentActive(
          's1',
          includeMember: (id) => id != 'parked' && id != 'busy',
        ),
        isFalse,
      );
    });

    group('optimistic ask dismiss + reconciliation', () {
      const questions = [
        AgentAskUserQuestion(
          question: 'Pick one?',
          options: [
            AgentAskUserOption(label: 'A'),
            AgentAskUserOption(label: 'B'),
          ],
        ),
      ];

      const askWaiting = AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: 'question.asked',
        askRequestId: 'ask-1',
        askUserQuestions: questions,
      );

      test('markAskAnswered moves to working and retains lastEvent', () {
        final c = _cubit();
        c.applyEvent(
          sessionId: 's1',
          memberId: 'm1',
          event: askWaiting,
          skipPermissions: false,
        );

        c.markAskAnswered(sessionId: 's1', memberId: 'm1');

        final entry = c.state.entryFor(sessionId: 's1', memberId: 'm1');
        expect(entry?.attention, AgentSeatAttention.working);
        expect(entry?.lastEvent, askWaiting);
        expect(entry?.dismissedAskRequestId, 'ask-1');
        expect(entry?.askReplyError, isNull);
      });

      test(
        'markAskAnswered no-ops when not waiting or missing askRequestId',
        () {
          final c = _cubit();

          // Missing entry.
          c.markAskAnswered(sessionId: 's1', memberId: 'm1');
          expect(c.state.seats, isEmpty);

          // Working (not waiting).
          c.applyEvent(
            sessionId: 's1',
            memberId: 'm1',
            event: const AgentStatusEvent(state: AgentSeatAttention.working),
            skipPermissions: false,
          );
          final afterWorking = c.state;
          c.markAskAnswered(sessionId: 's1', memberId: 'm1');
          expect(c.state, same(afterWorking));

          // Waiting but no askRequestId (permission-style wait).
          c.applyEvent(
            sessionId: 's1',
            memberId: 'm1',
            event: const AgentStatusEvent(
              state: AgentSeatAttention.waiting,
              hookEventName: 'PermissionRequest',
              toolName: 'Bash',
            ),
            skipPermissions: false,
          );
          final afterPermissionWait = c.state;
          c.markAskAnswered(sessionId: 's1', memberId: 'm1');
          expect(c.state, same(afterPermissionWait));

          // Waiting with empty askRequestId.
          c.applyEvent(
            sessionId: 's1',
            memberId: 'm1',
            event: const AgentStatusEvent(
              state: AgentSeatAttention.waiting,
              hookEventName: 'question.asked',
              askRequestId: '',
              askUserQuestions: questions,
            ),
            skipPermissions: false,
          );
          final afterEmptyAskId = c.state;
          c.markAskAnswered(sessionId: 's1', memberId: 'm1');
          expect(c.state, same(afterEmptyAskId));
        },
      );

      test('same askRequestId waiting after dismiss is ignored', () {
        final c = _cubit();
        c.applyEvent(
          sessionId: 's1',
          memberId: 'm1',
          event: askWaiting,
          skipPermissions: false,
        );
        c.markAskAnswered(sessionId: 's1', memberId: 'm1');

        c.applyEvent(
          sessionId: 's1',
          memberId: 'm1',
          event: askWaiting,
          skipPermissions: false,
        );

        final entry = c.state.entryFor(sessionId: 's1', memberId: 'm1');
        expect(entry?.attention, AgentSeatAttention.working);
        expect(entry?.dismissedAskRequestId, 'ask-1');
        expect(entry?.lastEvent, askWaiting);
      });

      test('reply_failed restores waiting from retained lastEvent', () {
        final c = _cubit();
        c.applyEvent(
          sessionId: 's1',
          memberId: 'm1',
          event: askWaiting,
          skipPermissions: false,
        );
        c.markAskAnswered(sessionId: 's1', memberId: 'm1');

        c.applyEvent(
          sessionId: 's1',
          memberId: 'm1',
          event: const AgentStatusEvent(
            state: AgentSeatAttention.working,
            hookEventName: 'question.reply_failed',
            askRequestId: 'ask-1',
            message: 'boom',
            restoreAskWaiting: true,
          ),
          skipPermissions: false,
        );

        final entry = c.state.entryFor(sessionId: 's1', memberId: 'm1');
        expect(entry?.attention, AgentSeatAttention.waiting);
        expect(entry?.askReplyError, 'boom');
        expect(entry?.dismissedAskRequestId, isNull);
        expect(entry?.lastEvent?.askUserQuestions, questions);
        expect(entry?.lastEvent?.askRequestId, 'ask-1');
      });

      test('new different askRequestId waiting replaces dismissed id', () {
        final c = _cubit();
        c.applyEvent(
          sessionId: 's1',
          memberId: 'm1',
          event: askWaiting,
          skipPermissions: false,
        );
        c.markAskAnswered(sessionId: 's1', memberId: 'm1');

        const nextAsk = AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'question.asked',
          askRequestId: 'ask-2',
          askUserQuestions: [
            AgentAskUserQuestion(
              question: 'Next?',
              options: [AgentAskUserOption(label: 'Y')],
            ),
          ],
        );
        c.applyEvent(
          sessionId: 's1',
          memberId: 'm1',
          event: nextAsk,
          skipPermissions: false,
        );

        final entry = c.state.entryFor(sessionId: 's1', memberId: 'm1');
        expect(entry?.attention, AgentSeatAttention.waiting);
        expect(entry?.dismissedAskRequestId, isNull);
        expect(entry?.lastEvent, nextAsk);
      });
    });
  });
}
