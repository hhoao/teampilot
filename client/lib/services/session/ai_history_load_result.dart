import 'package:ai_message_core/ai_message_core.dart';

/// Parsed History messages plus inflated subagent attachment index.
class AiHistoryLoadResult {
  const AiHistoryLoadResult({
    required this.messages,
    this.subagentAttachments = const {},
  });

  final List<AiMessage> messages;
  final Map<String, AiSubagentAttachment> subagentAttachments;
}
