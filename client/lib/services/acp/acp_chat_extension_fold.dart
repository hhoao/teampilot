import 'package:ai_message_core/ai_message_core.dart';

import 'acp_client_extensions.dart';
import 'acp_session.dart';

/// Folds a Cursor ACP extension notification into the chat document.
///
/// Unknown updates return [messages] unchanged (same list identity).
List<AiMessage> foldAcpExtensionNotification({
  required List<AiMessage> messages,
  required AcpSessionUpdate update,
  required String Function() newId,
}) {
  return switch (update) {
    AcpTodoListUpdate() => _foldTodos(messages, update.notification, newId),
    AcpTaskUpdate() => _appendPart(
      messages,
      AiToolCallPart(
        toolCallId: update.notification.toolCallId,
        toolName: update.notification.subagentType,
        category: AiToolCallCategory.subagent,
        status: AiToolCallStatus.complete,
        args: {'description': update.notification.description},
      ),
      newId,
    ),
    AcpGeneratedImageUpdate() => _appendPart(
      messages,
      AiToolCallPart(
        toolCallId: update.notification.toolCallId,
        toolName: 'generate_image',
        status: AiToolCallStatus.complete,
        args: {
          'description': update.notification.description,
          if (update.notification.filePath != null)
            'filePath': update.notification.filePath,
        },
      ),
      newId,
    ),
    _ => messages,
  };
}

List<AiMessage> _foldTodos(
  List<AiMessage> messages,
  AcpTodoListNotification notification,
  String Function() newId,
) {
  final incoming = _todoMaps(notification.todos);
  if (messages.isNotEmpty && messages.last.role == AiRole.assistant) {
    final tip = messages.last;
    final parts = [...tip.parts];
    for (var i = parts.length - 1; i >= 0; i--) {
      final part = parts[i];
      if (part is! AiToolCallPart || part.toolName != 'TodoWrite') continue;
      final todos = notification.merge
          ? _mergeTodos(_asTodoMaps(part.args?['todos']), notification.todos)
          : incoming;
      parts[i] = part.copyWith(
        category: AiToolCallCategory.task,
        status: AiToolCallStatus.complete,
        args: {'todos': todos, 'merge': notification.merge},
      );
      return [
        ...messages.sublist(0, messages.length - 1),
        tip.copyWith(parts: parts),
      ];
    }
  }
  return _appendPart(messages, _todoPart(notification, incoming), newId);
}

AiToolCallPart _todoPart(
  AcpTodoListNotification notification,
  List<Map<String, Object?>> todos,
) => AiToolCallPart(
  toolCallId: 'TodoWrite',
  toolName: 'TodoWrite',
  category: AiToolCallCategory.task,
  status: AiToolCallStatus.complete,
  args: {'todos': todos, 'merge': notification.merge},
);

List<AiMessage> _appendPart(
  List<AiMessage> messages,
  AiToolCallPart part,
  String Function() newId,
) {
  if (messages.isNotEmpty && messages.last.role == AiRole.assistant) {
    final tip = messages.last;
    return [
      ...messages.sublist(0, messages.length - 1),
      tip.copyWith(parts: [...tip.parts, part]),
    ];
  }
  return [
    ...messages,
    AiMessage(
      id: newId(),
      role: AiRole.assistant,
      parts: [part],
      createdAt: DateTime.now(),
    ),
  ];
}

List<Map<String, Object?>> _todoMaps(List<AcpTodoItem> items) => [
  for (final item in items)
    {'id': item.id, 'content': item.content, 'status': item.status},
];

List<Map<String, Object?>> _asTodoMaps(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map)
        {
          'id': '${item['id'] ?? ''}',
          'content': '${item['content'] ?? ''}',
          'status': '${item['status'] ?? ''}',
        },
  ];
}

List<Map<String, Object?>> _mergeTodos(
  List<Map<String, Object?>> previous,
  List<AcpTodoItem> incoming,
) {
  final out = [for (final item in previous) Map<String, Object?>.from(item)];
  for (final item in incoming) {
    final index = out.indexWhere((map) => map['id'] == item.id);
    if (index < 0) {
      out.add({'id': item.id, 'content': item.content, 'status': item.status});
      continue;
    }
    final priorContent = '${out[index]['content'] ?? ''}';
    out[index] = {
      'id': item.id,
      'content': item.content.isEmpty ? priorContent : item.content,
      'status': item.status,
    };
  }
  return out;
}
