import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/tasks/cli_task_board.dart';

AiMessage _assistant(AiToolCallPart part) =>
    AiMessage(id: 'm', role: AiRole.assistant, parts: [part]);

AiToolCallPart _create({
  Map<String, Object?>? args,
  Object? result,
}) =>
    AiToolCallPart(
      toolCallId: 'c',
      toolName: 'TaskCreate',
      args: args,
      result: result,
      status: AiToolCallStatus.complete,
    );

AiToolCallPart _update(Map<String, Object?> args) => AiToolCallPart(
  toolCallId: 'u',
  toolName: 'TaskUpdate',
  args: args,
  status: AiToolCallStatus.complete,
);

void main() {
  test('TaskCreate appends a pending task with subject/description/activeForm',
      () {
    final board = reduceCliTaskBoard([
      _assistant(_create(args: {
        'subject': 'T1: do a thing',
        'description': 'details',
        'activeForm': 'Doing a thing',
      })),
    ]);
    expect(board.totalCount, 1);
    final task = board.tasks.single;
    expect(task.subject, 'T1: do a thing');
    expect(task.description, 'details');
    expect(task.activeForm, 'Doing a thing');
    expect(task.status, CliTaskStatus.pending);
    expect(board.completedCount, 0);
  });

  test('TaskCreate reads taskId from the correlated result', () {
    final board = reduceCliTaskBoard([
      _assistant(_create(
        args: {'subject': 'T1'},
        result: {'taskId': '9', 'subject': 'T1'},
      )),
    ]);
    expect(board.tasks.single.taskId, '9');
  });

  test('TaskCreate reads taskId from a string result', () {
    final board = reduceCliTaskBoard([
      _assistant(_create(
        args: {'subject': 'do a thing'},
        result: 'Task #1 created successfully: do a thing',
      )),
    ]);
    expect(board.tasks.single.taskId, '1');
  });

  test('TaskUpdate without status is ignored (no placeholder)', () {
    final board = reduceCliTaskBoard([
      _assistant(_update({'taskId': '2', 'addBlockedBy': ['1']})),
    ]);
    expect(board.totalCount, 0);
  });

  test('TaskUpdate flips status when taskId matches a created task', () {
    final board = reduceCliTaskBoard([
      _assistant(_create(args: {'subject': 'T1'}, result: {'taskId': '9'})),
      _assistant(_update({'taskId': '9', 'status': 'in_progress'})),
    ]);
    expect(board.totalCount, 1);
    expect(board.tasks.single.status, CliTaskStatus.inProgress);
  });

  test('TaskUpdate before any matching create adds a placeholder', () {
    final board = reduceCliTaskBoard([
      _assistant(_update({'taskId': '9', 'status': 'completed'})),
    ]);
    expect(board.totalCount, 1);
    expect(board.tasks.single.subject, '');
    expect(board.tasks.single.taskId, '9');
    expect(board.tasks.single.status, CliTaskStatus.completed);
    expect(board.completedCount, 1);
  });

  test('unknown status string maps to unknown; tool name is case-insensitive',
      () {
    final board = reduceCliTaskBoard([
      AiMessage(
        id: 'm',
        role: AiRole.assistant,
        parts: [
          AiToolCallPart(
            toolCallId: 'c',
            toolName: 'taskupdate',
            args: {'taskId': '1', 'status': 'weird'},
            status: AiToolCallStatus.complete,
          ),
        ],
      ),
    ]);
    expect(board.tasks.single.status, CliTaskStatus.unknown);
  });

  test('non-task tools and user messages are ignored', () {
    final board = reduceCliTaskBoard([
      _assistant(AiToolCallPart(
        toolCallId: 'c',
        toolName: 'Bash',
        args: const {'command': 'ls'},
        status: AiToolCallStatus.complete,
      )),
      const AiMessage(
        id: 'u',
        role: AiRole.user,
        parts: [AiTextPart(text: 'hi')],
      ),
    ]);
    expect(board.totalCount, 0);
  });

  test('tasks keep creation order', () {
    final board = reduceCliTaskBoard([
      _assistant(_create(args: {'subject': 'A'})),
      _assistant(_create(args: {'subject': 'B'})),
    ]);
    expect(board.tasks.map((t) => t.subject).toList(), ['A', 'B']);
  });
}
