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

  /// Cheap fingerprint of on-disk side-transcript data that can move while a
  /// sub-agent is still running (the parent transcript mtime stays fixed until
  /// the tool result lands). [AiHistoryLoader] uses this to decide whether
  /// cached subagent attachments need re-inflation on a live refresh.
  ///
  /// Return null when the layout cannot be fingerprinted cheaply (or no side
  /// data exists yet) — the loader then keeps parent-transcript-only cache
  /// semantics.
  Future<String?> fingerprint({
    required SessionHistoryContext ctx,
    required String? rootTranscriptPath,
  }) async => null;
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

  @override
  Future<String?> fingerprint({
    required SessionHistoryContext ctx,
    required String? rootTranscriptPath,
  }) async => null;
}
