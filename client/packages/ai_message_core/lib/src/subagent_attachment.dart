import 'message.dart';

enum AiSubagentAttachmentSource { sideTranscript, toolResult }

sealed class SubagentSideHandle {
  const SubagentSideHandle();
}

final class SubagentFileHandle extends SubagentSideHandle {
  const SubagentFileHandle(this.path);
  final String path;
}

final class SubagentSessionHandle extends SubagentSideHandle {
  const SubagentSessionHandle(this.sessionId);
  final String sessionId;
}

class AiSubagentAttachment {
  const AiSubagentAttachment({
    required this.toolCallId,
    required this.messages,
    required this.source,
    this.title,
    this.handle,
  });

  final String toolCallId;
  final List<AiMessage> messages;
  final AiSubagentAttachmentSource source;
  final String? title;
  final SubagentSideHandle? handle;

  /// File-handle path for debug/compat; null for session handles.
  String? get sidePath {
    final h = handle;
    if (h is SubagentFileHandle) return h.path;
    return null;
  }
}

const kAiSubagentToolNames = {'agent', 'task', 'spawn_agent'};

bool isAiSubagentToolName(String toolName) =>
    kAiSubagentToolNames.contains(toolName.trim().toLowerCase());

String? subagentTitleFromPart(AiToolCallPart part) {
  final args = part.args;
  if (args != null) {
    final description = _trimmedString(args['description']);
    if (description != null) return description;
    final prompt = _trimmedString(args['prompt']);
    if (prompt != null) return prompt;
  }
  return null;
}

String? subagentAgentIdFromPart(AiToolCallPart part) {
  final fromArgs = _agentIdFromMap(part.args);
  if (fromArgs != null) return fromArgs;

  final result = part.result;
  if (result is Map) {
    return _agentIdFromMap(Map<String, Object?>.from(result));
  }
  return null;
}

List<AiMessage> syntheticSubagentMessagesFromResult({
  required String toolCallId,
  required Object? result,
}) {
  if (result == null) return const [];

  final text = switch (result) {
    String s => s.trim(),
    _ => result.toString().trim(),
  };
  if (text.isEmpty) return const [];

  return [
    AiMessage(
      id: 'subagent-result-$toolCallId',
      role: AiRole.assistant,
      parts: [AiTextPart(text: text)],
    ),
  ];
}

String? _trimmedString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _agentIdFromMap(Map<String, Object?>? map) {
  if (map == null) return null;
  for (final key in const ['agentId', 'agent_id']) {
    final value = map[key];
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
  }
  return null;
}
