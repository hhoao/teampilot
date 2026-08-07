import 'package:ai_message_core/ai_message_core.dart';

import '../../../../session/session_history_context.dart';

class SubagentSideResolveResult {
  const SubagentSideResolveResult({
    required this.messages,
    required this.handle,
    this.workflow,
  });
  final List<AiMessage> messages;
  final SubagentSideHandle handle;

  /// Present when the resolved tool call is a Claude `Workflow` run; carries
  /// run metadata plus per-agent transcripts.
  final SubagentWorkflowInfo? workflow;
}

abstract interface class SubagentSideResolver {
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required SubagentSideHandle? parentHandle,
    required String? rootTranscriptPath,
    DateTime? toolCallAt,
  });
}

/// Always miss — temporary binder until later tasks.
final class NullSubagentSideResolver implements SubagentSideResolver {
  const NullSubagentSideResolver();
  @override
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required SubagentSideHandle? parentHandle,
    required String? rootTranscriptPath,
    DateTime? toolCallAt,
  }) async => null;
}
