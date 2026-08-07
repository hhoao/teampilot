import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/tasks/cli_task_board_controller.dart';

AiToolCallPart _create(String subject) => AiToolCallPart(
  toolCallId: 'c',
  toolName: 'TaskCreate',
  args: {'subject': subject},
  status: AiToolCallStatus.complete,
);

void main() {
  test('board reflects runtime messages and updates on change', () async {
    final runtime = ExternalStoreAiThreadRuntime();
    final controller = CliTaskBoardController(runtime);
    addTearDown(() {
      controller.dispose();
      runtime.close();
    });

    expect(controller.board.totalCount, 0);

    runtime.setMessages([
      AiMessage(id: 'm1', role: AiRole.assistant, parts: [_create('A')]),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.board.totalCount, 1);
    expect(controller.board.tasks.single.subject, 'A');

    runtime.setMessages([
      AiMessage(id: 'm1', role: AiRole.assistant, parts: [_create('A')]),
      AiMessage(id: 'm2', role: AiRole.assistant, parts: [_create('B')]),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.board.totalCount, 2);

    runtime.setMessages(const []);
    await Future<void>.delayed(Duration.zero);
    expect(controller.board.totalCount, 0);
  });

  test('does not re-derive when message instances are unchanged', () async {
    final runtime = ExternalStoreAiThreadRuntime();
    final controller = CliTaskBoardController(runtime);
    addTearDown(() {
      controller.dispose();
      runtime.close();
    });
    var notified = 0;
    controller.addListener(() => notified++);

    final message = AiMessage(
      id: 'm1',
      role: AiRole.assistant,
      parts: [_create('A')],
    );
    runtime.setMessages([message]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.board.totalCount, 1);

    // Reset the counter so it measures only the second feed: feeding the same
    // message instance again must not re-derive or notify.
    notified = 0;
    // Same message instance, new list wrapper → the runtime reuses the
    // instance and does not notify; the controller must not re-derive either.
    runtime.setMessages([message]);
    await Future<void>.delayed(Duration.zero);
    expect(notified, 0);
  });

  test('dispose cancels the runtime subscription', () async {
    final runtime = ExternalStoreAiThreadRuntime();
    final controller = CliTaskBoardController(runtime);
    controller.dispose();
    runtime.setMessages([
      AiMessage(id: 'm1', role: AiRole.assistant, parts: [_create('A')]),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.board.totalCount, 0);
    runtime.close();
  });
}
