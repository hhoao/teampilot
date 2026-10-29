import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_chat_extension_fold.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';

AiToolCallPart _todoWriteOf(List<AiMessage> messages) => messages.single.parts
    .whereType<AiToolCallPart>()
    .singleWhere((part) => part.toolName == 'TodoWrite');

List<Map<String, Object?>> _todosOf(List<AiMessage> messages) {
  final todos = _todoWriteOf(messages).args!['todos'] as List;
  return [for (final item in todos) Map<String, Object?>.from(item as Map)];
}

void main() {
  var seq = 0;
  String newId() => 'id-${seq++}';

  setUp(() => seq = 0);

  test(
    'merge:true upserts by id and keeps prior content when incoming omits it',
    () {
      final seeded = foldAcpExtensionNotification(
        messages: const [],
        update: const AcpTodoListUpdate(
          AcpTodoListNotification(
            todos: [
              AcpTodoItem(id: 'a', content: 'Task A', status: 'in_progress'),
              AcpTodoItem(id: 'b', content: 'Task B', status: 'pending'),
            ],
            merge: false,
          ),
        ),
        newId: newId,
      );

      final merged = foldAcpExtensionNotification(
        messages: seeded,
        update: const AcpTodoListUpdate(
          AcpTodoListNotification(
            todos: [
              AcpTodoItem(id: 'a', content: '', status: 'completed'),
              AcpTodoItem(id: 'c', content: 'Task C', status: 'in_progress'),
            ],
            merge: true,
          ),
        ),
        newId: newId,
      );

      expect(merged, hasLength(1));
      expect(merged.single.id, 'id-0');
      expect(merged.single.role, AiRole.assistant);
      expect(merged.single.createdAt, isNotNull);

      final part = _todoWriteOf(merged);
      expect(part.category, AiToolCallCategory.task);
      expect(part.status, AiToolCallStatus.complete);
      expect(part.args?['merge'], isTrue);
      expect(_todosOf(merged), [
        {'id': 'a', 'content': 'Task A', 'status': 'completed'},
        {'id': 'b', 'content': 'Task B', 'status': 'pending'},
        {'id': 'c', 'content': 'Task C', 'status': 'in_progress'},
      ]);
    },
  );

  test('merge:false replaces the todo list', () {
    final seeded = foldAcpExtensionNotification(
      messages: const [],
      update: const AcpTodoListUpdate(
        AcpTodoListNotification(
          todos: [
            AcpTodoItem(id: 'a', content: 'Task A', status: 'pending'),
            AcpTodoItem(id: 'b', content: 'Task B', status: 'pending'),
          ],
          merge: false,
        ),
      ),
      newId: newId,
    );

    final replaced = foldAcpExtensionNotification(
      messages: seeded,
      update: const AcpTodoListUpdate(
        AcpTodoListNotification(
          todos: [
            AcpTodoItem(id: 'd', content: 'Task D', status: 'in_progress'),
          ],
          merge: false,
        ),
      ),
      newId: newId,
    );

    expect(_todosOf(replaced), [
      {'id': 'd', 'content': 'Task D', 'status': 'in_progress'},
    ]);
    expect(_todoWriteOf(replaced).args?['merge'], isFalse);
  });

  test('ACP plan entries replace the todo slot as a snapshot', () {
    final seeded = foldAcpExtensionNotification(
      messages: const [],
      update: const AcpTodoListUpdate(
        AcpTodoListNotification(
          todos: [AcpTodoItem(id: 'a', content: 'Task A', status: 'pending')],
          merge: false,
        ),
      ),
      newId: newId,
    );

    final folded = foldAcpExtensionNotification(
      messages: seeded,
      update: const AcpPlan(
        entries: [
          AcpPlanEntry(
            content: 'Inspect the tab layout',
            priority: AcpPlanEntryPriority.high,
            status: AcpPlanEntryStatus.completed,
          ),
          AcpPlanEntry(
            content: 'Patch the sizing math',
            priority: AcpPlanEntryPriority.medium,
            status: AcpPlanEntryStatus.inProgress,
          ),
          AcpPlanEntry(
            content: '   ',
            priority: AcpPlanEntryPriority.low,
            status: AcpPlanEntryStatus.pending,
          ),
        ],
      ),
      newId: newId,
    );

    expect(folded, hasLength(1));
    expect(_todosOf(folded), [
      {'id': '1', 'content': 'Inspect the tab layout', 'status': 'completed'},
      {'id': '2', 'content': 'Patch the sizing math', 'status': 'in_progress'},
    ]);
    expect(_todoWriteOf(folded).args?['merge'], isFalse);
  });

  test('task appends a complete subagent tool part', () {
    final existing = [
      AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: const [AiTextPart(text: 'hi')],
      ),
    ];
    final folded = foldAcpExtensionNotification(
      messages: existing,
      update: const AcpTaskUpdate(
        AcpTaskNotification(
          toolCallId: 't1',
          description: 'Explore the repo',
          subagentType: 'explore',
        ),
      ),
      newId: newId,
    );

    expect(folded, hasLength(1));
    expect(folded.single.id, 'a1');
    expect(folded.single.parts, hasLength(2));
    final part = folded.single.parts.last as AiToolCallPart;
    expect(part.toolCallId, 't1');
    expect(part.toolName, 'explore');
    expect(part.category, AiToolCallCategory.subagent);
    expect(part.status, AiToolCallStatus.complete);
    expect(part.args, {'description': 'Explore the repo'});
  });

  test('image args include filePath only when present', () {
    final withPath = foldAcpExtensionNotification(
      messages: const [],
      update: const AcpGeneratedImageUpdate(
        AcpGeneratedImageNotification(
          toolCallId: 'img-1',
          description: 'a cat',
          filePath: '/tmp/cat.png',
        ),
      ),
      newId: newId,
    );
    final withPathPart = withPath.single.parts.single as AiToolCallPart;
    expect(withPathPart.toolCallId, 'img-1');
    expect(withPathPart.toolName, 'generate_image');
    expect(withPathPart.status, AiToolCallStatus.complete);
    expect(withPathPart.args, {
      'description': 'a cat',
      'filePath': '/tmp/cat.png',
    });

    final withoutPath = foldAcpExtensionNotification(
      messages: const [],
      update: const AcpGeneratedImageUpdate(
        AcpGeneratedImageNotification(
          toolCallId: 'img-2',
          description: 'a dog',
        ),
      ),
      newId: newId,
    );
    final withoutPathPart = withoutPath.single.parts.single as AiToolCallPart;
    expect(withoutPathPart.args, {'description': 'a dog'});
    expect(withoutPathPart.args!.containsKey('filePath'), isFalse);
  });

  test('other updates return the same list identity', () {
    final messages = [
      AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: const [AiTextPart(text: 'hi')],
      ),
    ];
    final result = foldAcpExtensionNotification(
      messages: messages,
      update: const AcpStop(kind: AcpStopKind.endTurn),
      newId: newId,
    );
    expect(identical(result, messages), isTrue);
  });
}
