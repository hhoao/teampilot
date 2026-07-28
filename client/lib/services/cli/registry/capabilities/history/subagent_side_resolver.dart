import 'package:ai_message_core/ai_message_core.dart';

import '../../../../session/session_history_context.dart';

class SubagentSideResolveResult {
  const SubagentSideResolveResult({
    required this.messages,
    required this.handle,
  });
  final List<AiMessage> messages;
  final SubagentSideHandle handle;
}

abstract interface class SubagentSideResolver {
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required SubagentSideHandle? parentHandle,
    required String? rootTranscriptPath,
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
  }) async => null;
}
