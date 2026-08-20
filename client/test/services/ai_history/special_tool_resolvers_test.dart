import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ai_history/special_tool_resolvers.dart';

void main() {
  group('TranscriptAiTaskToolResolver', () {
    const resolver = TranscriptAiTaskToolResolver();

    test('parses TodoWrite items and fills merge content', () {
      const filled = TranscriptAiTaskToolResolver(
        contentById: {'12': 'Wire builders'},
      );
      final target = filled.resolve(
        const AiToolCallPart(
          toolCallId: 't',
          toolName: 'TodoWrite',
          args: {
            'todos': [
              {'id': '12', 'status': 'completed'},
              {'id': '13', 'content': 'Verify tests', 'status': 'pending'},
            ],
          },
        ),
      );
      expect(target, isA<AiTodoListTarget>());
      final todos = target! as AiTodoListTarget;
      expect(todos.items.map((i) => i.content), [
        'Wire builders',
        'Verify tests',
      ]);
      expect(todos.items.first.status, AiTaskStatus.completed);
    });

    test('parses TaskCreate subject', () {
      final target = resolver.resolve(
        const AiToolCallPart(
          toolCallId: 'c',
          toolName: 'TaskCreate',
          args: {'subject': 'T1: do a thing', 'description': 'details'},
        ),
      );
      expect(target, isA<AiTaskCreateTarget>());
      expect((target! as AiTaskCreateTarget).subject, 'T1: do a thing');
    });

    test('parses TaskUpdate status', () {
      final target = resolver.resolve(
        const AiToolCallPart(
          toolCallId: 'u',
          toolName: 'TaskUpdate',
          args: {'taskId': '9', 'status': 'in_progress'},
        ),
      );
      expect(target, isA<AiTaskUpdateTarget>());
      expect((target! as AiTaskUpdateTarget).taskId, '9');
      expect((target! as AiTaskUpdateTarget).status, AiTaskStatus.inProgress);
    });

    test('ignores unrelated tools', () {
      expect(
        resolver.resolve(
          const AiToolCallPart(toolCallId: 'b', toolName: 'Bash'),
        ),
        isNull,
      );
    });
  });

  group('TranscriptAiAskUserResolver', () {
    const resolver = TranscriptAiAskUserResolver();

    test('registers ask-user tool names', () {
      expect(
        TranscriptAiAskUserResolver.toolNames,
        containsAll([
          'askuserquestion',
          'ask_user_question',
          'ask_user',
          'askquestion',
          'question',
        ]),
      );
    });

    test('parses questions and answers', () {
      final target = resolver.resolve(
        const AiToolCallPart(
          toolCallId: 'q',
          toolName: 'AskUserQuestion',
          args: {
            'questions': [
              {
                'question': 'How is the weather today?',
                'options': ['Sunny', 'Rainy'],
              },
            ],
          },
          result: {
            'answers': {'How is the weather today?': 'Sunny'},
          },
          status: AiToolCallStatus.complete,
        ),
      );
      expect(target, isNotNull);
      expect(target!.asking, isFalse);
      expect(target.items.single.question, 'How is the weather today?');
      expect(target.items.single.answer, 'Sunny');
    });

    test('returns null when questions cannot be parsed', () {
      expect(
        resolver.resolve(
          const AiToolCallPart(
            toolCallId: 'q',
            toolName: 'AskUserQuestion',
            args: {'foo': 'bar'},
          ),
        ),
        isNull,
      );
    });
  });

  group('AttachmentAiWorkflowResolver', () {
    test('resolves workflow attachments by toolCallId', () {
      final resolver = AttachmentAiWorkflowResolver(
        attachments: {
          'call_00_wf': const AiSubagentAttachment(
            toolCallId: 'call_00_wf',
            messages: [],
            source: AiSubagentAttachmentSource.sideTranscript,
            workflow: SubagentWorkflowInfo(
              runId: 'wf_run1',
              workflowName: 'migrate',
            ),
          ),
        },
      );
      final target = resolver.resolve(
        const AiToolCallPart(toolCallId: 'call_00_wf', toolName: 'Workflow'),
      );
      expect(target, isNotNull);
      expect(target!.workflow?.workflowName, 'migrate');
    });

    test('returns empty target when attachment is missing', () {
      const resolver = AttachmentAiWorkflowResolver(attachments: {});
      final target = resolver.resolve(
        const AiToolCallPart(toolCallId: 'missing', toolName: 'Workflow'),
      );
      expect(target, isNotNull);
      expect(target!.workflow, isNull);
    });

    test('ignores non-workflow tools', () {
      const resolver = AttachmentAiWorkflowResolver(attachments: {});
      expect(
        resolver.resolve(
          const AiToolCallPart(toolCallId: 't', toolName: 'Task'),
        ),
        isNull,
      );
    });
  });
}
