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
    if (_shouldSkipEmptyTextOnly(parts)) {
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
    return [AiTextPart(text: content)];
  }
  if (content is List<AiMessagePart>) {
    return List<AiMessagePart>.from(content);
  }
  throw ArgumentError(
    'ThreadMessageLike.content must be String or List<AiMessagePart>',
  );
}

bool _shouldSkipEmptyTextOnly(List<AiMessagePart> parts) {
  if (parts.isEmpty) {
    return true;
  }
  if (parts.length == 1 && parts.single is AiTextPart) {
    return (parts.single as AiTextPart).text.isEmpty;
  }
  return false;
}
