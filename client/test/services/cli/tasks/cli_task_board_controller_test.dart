import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/tasks/cli_task_board.dart';
import 'package:teampilot/services/cli/tasks/cli_task_board_controller.dart';

AiToolCallPart _create(String subject, {Object? result}) => AiToolCallPart(
  toolCallId: 'c-$subject',
  toolName: 'TaskCreate',
  args: {'subject': subject},
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
  test('derives from full loaded messages, not the visible thread slice',
      () async {
    final runtime = ExternalStoreAiThreadRuntime();
    var full = <AiMessage>[];
    final controller = CliTaskBoardController(
      runtime: runtime,
      loadedMessages: () => full,
    );
    addTearDown(() {
      controller.dispose();
      runtime.close();
    });

    expect(controller.board.totalCount, 0);

    // Full transcript has the create; the visible slice (what a large
    // session's thread shows) only has the update that references it.
    full = [
      AiMessage(
        id: 'm1',
        role: AiRole.assistant,
        parts: [_create('A', result: {'taskId': '1'})],
      ),
    ];
    runtime.setMessages([
      AiMessage(
        id: 'm2',
        role: AiRole.assistant,
        parts: [_update({'taskId': '1', 'status': 'in_progress'})],
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.board.totalCount, 1);
    expect(controller.board.tasks.single.subject, 'A');
    expect(controller.board.tasks.single.status, CliTaskStatus.pending);
  });

  test('re-derives when the full messages change', () async {
    final runtime = ExternalStoreAiThreadRuntime();
    var full = <AiMessage>[];
    final controller = CliTaskBoardController(
      runtime: runtime,
      loadedMessages: () => full,
    );
    addTearDown(() {
      controller.dispose();
      runtime.close();
    });

    full = [
      AiMessage(
        id: 'm1',
        role: AiRole.assistant,
        parts: [_create('A', result: {'taskId': '1'})],
      ),
    ];
    runtime.setMessages(full);
    await Future<void>.delayed(Duration.zero);
    expect(controller.board.tasks.single.status, CliTaskStatus.pending);

    full = [
      AiMessage(
        id: 'm1',
        role: AiRole.assistant,
        parts: [_create('A', result: {'taskId': '1'})],
      ),
      AiMessage(
        id: 'm2',
        role: AiRole.assistant,
        parts: [_update({'taskId': '1', 'status': 'in_progress'})],
      ),
    ];
    runtime.setMessages([full.last]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.board.tasks.single.status, CliTaskStatus.inProgress);
  });

  test('does not re-derive when message instances are unchanged', () async {
    final runtime = ExternalStoreAiThreadRuntime();
    final message = AiMessage(
      id: 'm1',
      role: AiRole.assistant,
      parts: [_create('A')],
    );
    var full = <AiMessage>[message];
    final controller = CliTaskBoardController(
      runtime: runtime,
      loadedMessages: () => full,
    );
    addTearDown(() {
      controller.dispose();
      runtime.close();
    });
    var notified = 0;
    controller.addListener(() => notified++);

    runtime.setMessages([message]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.board.totalCount, 1);

    // Same instances, same full list → the runtime does not notify and the
    // controller must not re-derive.
    notified = 0;
    runtime.setMessages([message]);
    await Future<void>.delayed(Duration.zero);
    expect(notified, 0);
  });

  test('dispose cancels the runtime subscription', () async {
    final runtime = ExternalStoreAiThreadRuntime();
    var full = <AiMessage>[];
    final controller = CliTaskBoardController(
      runtime: runtime,
      loadedMessages: () => full,
    );
    controller.dispose();
    full = [
      AiMessage(id: 'm1', role: AiRole.assistant, parts: [_create('A')]),
    ];
    runtime.setMessages(full);
    await Future<void>.delayed(Duration.zero);
    expect(controller.board.totalCount, 0);
    runtime.close();
  });
}
