enum AiRole { user, assistant, system }

sealed class AiMessagePart {}

class AiTextPart implements AiMessagePart {
  const AiTextPart({required this.text});

  final String text;
}

class AiToolCallPart implements AiMessagePart {
  const AiToolCallPart({
    required this.toolCallId,
    required this.toolName,
    this.args,
    this.argsText,
    this.result,
    this.isError = false,
  });

  final String toolCallId;
  final String toolName;
  final Map<String, Object?>? args;
  final String? argsText;
  final Object? result;
  final bool isError;
}

class AiReasoningPart implements AiMessagePart {
  const AiReasoningPart({required this.text});

  final String text;
}

enum AiMessageStatus { complete, incomplete, cancelled }

class AiMessage {
  const AiMessage({
    required this.id,
    required this.role,
    required this.parts,
    this.createdAt,
    this.status = AiMessageStatus.complete,
  });

  final String id;
  final AiRole role;
  final List<AiMessagePart> parts;
  final DateTime? createdAt;
  final AiMessageStatus status;
}
