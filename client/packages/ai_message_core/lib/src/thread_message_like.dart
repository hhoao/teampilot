import 'message.dart';

class ThreadMessageLike {
  const ThreadMessageLike({
    required this.role,
    required this.content,
    this.id,
    this.createdAt,
    this.status = AiMessageStatus.complete,
  });

  final AiRole role;

  /// `String` or `List<AiMessagePart>`.
  final Object content;
  final String? id;
  final DateTime? createdAt;
  final AiMessageStatus status;
}

List<AiMessage> normalizeThreadMessages(List<ThreadMessageLike> input) {
  final messages = <AiMessage>[];
  for (var i = 0; i < input.length; i++) {
    final item = input[i];
    final parts = _partsFromContent(item.content);
    if (parts.isEmpty) {
      continue;
    }
    messages.add(
      AiMessage(
        id: item.id ?? 'msg_$i',
        role: item.role,
        parts: parts,
        createdAt: item.createdAt,
        status: item.status,
      ),
    );
  }
  return messages;
}

List<AiMessagePart> _partsFromContent(Object content) {
  if (content is String) {
    if (content.isEmpty) {
      return const [];
    }
    return [AiTextPart(text: content)];
  }
  if (content is List<AiMessagePart>) {
    return content
        .where((part) => part is! AiTextPart || part.text.isNotEmpty)
        .toList();
  }
  throw ArgumentError(
    'ThreadMessageLike.content must be String or List<AiMessagePart>',
  );
}
