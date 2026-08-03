import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/agent_status/ask_user_question.dart';
import 'package:teampilot/services/agent_status/ask_user_question_hook_gate.dart';

void main() {
  const questions = [
    AgentAskUserQuestion(
      question: 'Pick?',
      options: [
        AgentAskUserOption(label: 'A'),
        AgentAskUserOption(label: 'B'),
      ],
    ),
  ];

  group('preserveAskUserQuestionPayload', () {
    test('keeps questions when PermissionRequest lacks tool_input', () {
      const previous = AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: 'PreToolUse',
        toolName: 'AskUserQuestion',
        toolUseId: 'toolu-1',
        askRequestId: 'toolu-1',
        askUserQuestions: questions,
      );
      const next = AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: 'PermissionRequest',
        toolName: 'AskUserQuestion',
      );

      final merged = preserveAskUserQuestionPayload(previous, next);
      expect(merged.askUserQuestions, questions);
      expect(merged.askRequestId, 'toolu-1');
      expect(merged.toolName, 'AskUserQuestion');
    });

    test('does not leak ask payload onto Bash permission waits', () {
      const previous = AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: 'PreToolUse',
        toolName: 'AskUserQuestion',
        askUserQuestions: questions,
      );
      const next = AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: 'PermissionRequest',
        toolName: 'Bash',
      );

      final merged = preserveAskUserQuestionPayload(previous, next);
      expect(merged.askUserQuestions, isNull);
      expect(merged.toolName, 'Bash');
    });
  });

  group('AskUserQuestionHookGate', () {
    test('complete unblocks wait with allow reply', () async {
      final gate = AskUserQuestionHookGate();
      final future = gate.wait(
        sessionId: 's',
        memberId: 'm',
        toolUseId: 't1',
      );
      expect(
        gate.complete(
          sessionId: 's',
          memberId: 'm',
          toolUseId: 't1',
          reply: AskUserQuestionHookReply.allow(
            questions: questions,
            answers: const {'Pick?': 'A'},
          ),
        ),
        isTrue,
      );
      final reply = await future;
      expect(reply?.reject, isFalse);
      expect(reply?.answers, {'Pick?': 'A'});
    });
  });
}
