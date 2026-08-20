import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  test('aiTaskStatusFromString maps known CLI strings', () {
    expect(aiTaskStatusFromString('pending'), AiTaskStatus.pending);
    expect(aiTaskStatusFromString('IN_PROGRESS'), AiTaskStatus.inProgress);
    expect(aiTaskStatusFromString('completed'), AiTaskStatus.completed);
    expect(aiTaskStatusFromString('cancelled'), AiTaskStatus.cancelled);
    expect(aiTaskStatusFromString('nope'), AiTaskStatus.unknown);
  });

  test('task targets preserve toolLabel', () {
    const todos = AiTodoListTarget(
      toolLabel: 'TodoWrite',
      items: [AiTodoItem(content: 'A', status: AiTaskStatus.pending)],
    );
    expect(todos.toolLabel, 'TodoWrite');
    expect(todos.items.single.content, 'A');

    const created = AiTaskCreateTarget(
      toolLabel: 'TaskCreate',
      subject: 'Do it',
    );
    expect(created.subject, 'Do it');
    expect(created.description, isEmpty);

    const updated = AiTaskUpdateTarget(
      toolLabel: 'TaskUpdate',
      taskId: '9',
      status: AiTaskStatus.inProgress,
    );
    expect(updated.taskId, '9');
    expect(updated.status, AiTaskStatus.inProgress);
  });

  test('AiTaskBoardItem carries subject and status', () {
    const item = AiTaskBoardItem(
      subject: 'Ship it',
      status: AiTaskStatus.inProgress,
    );
    expect(item.subject, 'Ship it');
    expect(item.status, AiTaskStatus.inProgress);
  });
}
