import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';

void main() {
  test('parses ask_question and encodes answered option ids', () {
    final pending = parseCursorBlockingRequest('cursor/ask_question', {
      'toolCallId': 'call_1',
      'questions': [
        {
          'id': 'q1',
          'prompt': 'Mode?',
          'options': [
            {'id': 'agent', 'label': 'Agent'},
            {'id': 'plan', 'label': 'Plan'},
          ],
        },
      ],
    });
    expect(pending, isA<AcpPendingAsk>());
    final ask = pending! as AcpPendingAsk;
    expect(ask.toolCallId, 'call_1');
    expect(ask.questions.single.id, 'q1');

    final encoded = encodeCursorBlockingReply(
      'cursor/ask_question',
      AcpAskHoldReply.answered(
        const AiAskUserSubmission(
          answers: [
            ['Agent'],
          ],
          optionIndices: [0],
        ),
      ),
      questions: ask.questions,
    );
    expect(encoded['outcome'], {
      'outcome': 'answered',
      'answers': [
        {
          'questionId': 'q1',
          'selectedOptionIds': ['agent'],
        },
      ],
    });
  });

  test('empty plan is not a pending request', () {
    expect(
      parseCursorBlockingRequest('cursor/create_plan', {
        'toolCallId': 'c',
        'plan': '',
      }),
      isNull,
    );
  });

  test('parses update_todos merge flag', () {
    final note = parseCursorNotification('cursor/update_todos', {
      'todos': [
        {'id': '1', 'content': 'A', 'status': 'pending'},
      ],
      'merge': true,
    });
    expect(note, isA<AcpTodoListNotification>());
    final todos = note! as AcpTodoListNotification;
    expect(todos.merge, isTrue);
    expect(todos.todos, hasLength(1));
    expect(todos.todos.single.id, '1');
    expect(todos.todos.single.content, 'A');
    expect(todos.todos.single.status, 'pending');
  });

  test('encodes skipped ask as nested skipped outcome', () {
    final encoded = encodeCursorBlockingReply(
      'cursor/ask_question',
      const AcpAskHoldReply.skipped(),
      questions: const [],
    );
    expect(encoded['outcome'], {'outcome': 'skipped'});
  });

  test('encodes cancelled ask as nested cancelled outcome', () {
    expect(
      encodeCursorBlockingReply(
        'cursor/ask_question',
        const AcpAskHoldReply.cancelled(),
        questions: const [],
      )['outcome'],
      {'outcome': 'cancelled'},
    );
    expect(
      encodeCursorBlockingReply(
        'cursor/ask_question',
        const AcpCancelledHoldReply(),
        questions: const [],
      )['outcome'],
      {'outcome': 'cancelled'},
    );
  });

  test('encodes accepted plan as nested accepted outcome', () {
    final pending = parseCursorBlockingRequest('cursor/create_plan', {
      'toolCallId': 'p1',
      'plan': '# Steps',
      'name': 'Ship',
      'overview': 'Do the thing',
    });
    expect(pending, isA<AcpPendingPlan>());
    final plan = pending! as AcpPendingPlan;
    expect(plan.toolCallId, 'p1');
    expect(plan.planText, '# Steps');
    expect(plan.name, 'Ship');
    expect(plan.overview, 'Do the thing');

    final encoded = encodeCursorBlockingReply(
      'cursor/create_plan',
      const AcpPlanHoldReply.accepted(),
      questions: const [],
    );
    expect(encoded['outcome'], {'outcome': 'accepted'});
  });

  test('encodes rejected plan as nested rejected outcome', () {
    final encoded = encodeCursorBlockingReply(
      'cursor/create_plan',
      const AcpPlanHoldReply.rejected('nope'),
      questions: const [],
    );
    expect(encoded['outcome'], {'outcome': 'rejected', 'reason': 'nope'});
  });

  test('encodes cancelled plan from shared cancelled hold', () {
    final encoded = encodeCursorBlockingReply(
      'cursor/create_plan',
      const AcpCancelledHoldReply(),
      questions: const [],
    );
    expect(encoded['outcome'], {'outcome': 'cancelled'});
  });

  test('parses custom subagentType map to string', () {
    final note = parseCursorNotification('cursor/task', {
      'toolCallId': 't1',
      'description': 'Explore the repo',
      'subagentType': {'custom': 'explore'},
    });
    expect(note, isA<AcpTaskNotification>());
    final task = note! as AcpTaskNotification;
    expect(task.toolCallId, 't1');
    expect(task.description, 'Explore the repo');
    expect(task.subagentType, 'explore');
  });

  test('foreign blocking method is not a pending request', () {
    expect(
      parseCursorBlockingRequest('session/request_permission', {
        'toolCallId': 'x',
        'questions': [
          {
            'prompt': 'Mode?',
            'options': [
              {'id': 'a', 'label': 'A'},
            ],
          },
        ],
      }),
      isNull,
    );
  });

  test('foreign notification method is not an extension payload', () {
    expect(
      parseCursorNotification('cursor/unknown', {
        'todos': [
          {'id': '1', 'content': 'A', 'status': 'pending'},
        ],
      }),
      isNull,
    );
  });

  test(
    'mismatched or unknown encodes stay cancelled so the hold cannot hang',
    () {
      const cancelled = {'outcome': 'cancelled'};
      expect(
        encodeCursorBlockingReply(
          'cursor/ask_question',
          const AcpPlanHoldReply.accepted(),
          questions: const [],
        )['outcome'],
        cancelled,
      );
      expect(
        encodeCursorBlockingReply(
          'session/foo',
          const AcpAskHoldReply.skipped(),
          questions: const [],
        )['outcome'],
        cancelled,
      );
      expect(
        encodeCursorBlockingReply(
          'cursor/ask_question',
          const AcpPermissionHoldReply(
            kind: AgentPermissionReplyKind.allowOnce,
          ),
          questions: const [],
        )['outcome'],
        cancelled,
      );
    },
  );

  test(
    'missing or non-list todos is not a notification; empty list is replace',
    () {
      expect(parseCursorNotification('cursor/update_todos', {}), isNull);
      expect(
        parseCursorNotification('cursor/update_todos', {'todos': 'nope'}),
        isNull,
      );

      final empty = parseCursorNotification('cursor/update_todos', {
        'todos': <Object?>[],
        'merge': false,
      });
      expect(empty, isA<AcpTodoListNotification>());
      final note = empty! as AcpTodoListNotification;
      expect(note.todos, isEmpty);
      expect(note.merge, isFalse);
    },
  );
}
