import 'message.dart';

enum AiSubagentAttachmentSource { sideTranscript, toolResult }

class AiSubagentAttachment {
  const AiSubagentAttachment({
    required this.toolCallId,
    required this.messages,
    required this.source,
    this.title,
    this.sidePath,
  });

  final String toolCallId;
  final List<AiMessage> messages;
  final AiSubagentAttachmentSource source;
  final String? title;
  final String? sidePath;
}

const kAiSubagentToolNames = {'agent', 'task'};

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
