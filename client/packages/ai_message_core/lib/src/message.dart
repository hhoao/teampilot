enum AiRole { user, assistant, system }

sealed class AiMessagePart {}

class AiTextPart implements AiMessagePart {
  const AiTextPart({required this.text});

  final String text;
}

/// assistant-ui ToolCallMessagePartStatus subset.
enum AiToolCallStatus { running, complete, incomplete, cancelled }

class AiToolCallPart implements AiMessagePart {
  const AiToolCallPart({
    required this.toolCallId,
    required this.toolName,
    this.args,
    this.argsText,
    this.result,
    this.status = AiToolCallStatus.incomplete,
    this.isError = false,
  });

  final String toolCallId;
  final String toolName;
  final Map<String, Object?>? args;
  final String? argsText;
  final Object? result;

  /// Lifecycle of the tool call (orthogonal to [isError]).
  final AiToolCallStatus status;

  /// True when the tool finished with an error payload (status is usually
  /// [AiToolCallStatus.complete]).
  final bool isError;

  bool get isCancelled => status == AiToolCallStatus.cancelled;

  bool get isRunning => status == AiToolCallStatus.running;

  AiToolCallPart copyWith({
    String? toolCallId,
    String? toolName,
    Map<String, Object?>? args,
    String? argsText,
    Object? result,
    bool clearResult = false,
    AiToolCallStatus? status,
    bool? isError,
  }) {
    return AiToolCallPart(
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      args: args ?? this.args,
      argsText: argsText ?? this.argsText,
      result: clearResult ? null : (result ?? this.result),
      status: status ?? this.status,
      isError: isError ?? this.isError,
    );
  }
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

  AiMessage copyWith({
    String? id,
    AiRole? role,
    List<AiMessagePart>? parts,
    DateTime? createdAt,
    bool clearCreatedAt = false,
    AiMessageStatus? status,
  }) {
    return AiMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      parts: parts ?? this.parts,
      createdAt: clearCreatedAt ? null : (createdAt ?? this.createdAt),
      status: status ?? this.status,
    );
  }
}

/// Merge runs of adjacent [AiRole.assistant] messages (cut on user/system).
/// Keeps the first message's id, createdAt, and status; concatenates parts.
List<AiMessage> coalesceAdjacentAssistants(List<AiMessage> messages) {
  if (messages.isEmpty) return const [];
  final out = <AiMessage>[];
  for (final msg in messages) {
    if (out.isNotEmpty &&
        out.last.role == AiRole.assistant &&
        msg.role == AiRole.assistant) {
      final prev = out.last;
      out[out.length - 1] = prev.copyWith(
        parts: [...prev.parts, ...msg.parts],
      );
    } else {
      out.add(msg);
    }
  }
  return out;
}

/// History finalize: unpaired tools stay incomplete; completed tools with a
/// result keep their status. Does not invent running state for disk transcripts.
List<AiMessage> finalizeAiMessagesForHistory(List<AiMessage> messages) {
  final coalesced = coalesceAdjacentAssistants(messages);
  return [
    for (final message in coalesced)
      message.copyWith(
        parts: [
          for (final part in message.parts)
            if (part is AiToolCallPart &&
                part.result == null &&
                part.status == AiToolCallStatus.complete &&
                !part.isError)
              part.copyWith(status: AiToolCallStatus.incomplete)
            else if (part is AiToolCallPart &&
                part.result == null &&
                part.status == AiToolCallStatus.running)
              part.copyWith(status: AiToolCallStatus.incomplete)
            else
              part,
        ],
      ),
  ];
}

/// Correlate a tool result onto the matching assistant [AiToolCallPart].
bool applyAiToolResult(
  List<AiMessage> messages, {
  required String toolUseId,
  required Object? result,
  bool isError = false,
  AiToolCallStatus status = AiToolCallStatus.complete,
}) {
  for (var i = 0; i < messages.length; i++) {
    final msg = messages[i];
    final parts = msg.parts;
    for (var j = 0; j < parts.length; j++) {
      final part = parts[j];
      if (part is! AiToolCallPart || part.toolCallId != toolUseId) continue;
      final updated = List<AiMessagePart>.of(parts);
      updated[j] = part.copyWith(
        result: result,
        status: status,
        isError: isError || part.isError,
      );
      messages[i] = msg.copyWith(parts: updated);
      return true;
    }
  }
  return false;
}
