import 'package:ai_message_core/ai_message_core.dart';

import '../../../../chat/conversation/history/session_history_context.dart';
import '../../../registry/capabilities/ai_history_capability.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';
import '../tool_call_resolvers.dart';

/// Antigravity history: Phase 1 is ACP-owned, so the app-owned
/// `acp-transcript.jsonl` is the transcript source and this adapter never
/// locates or parses the CLI-native brain transcript. `session/load` is not
/// used to supplement it.
final class AntigravityAiHistoryCapability implements AiHistoryCapability {
  const AntigravityAiHistoryCapability();

  static const _resolvers = AntigravityToolCallResolvers.instance;

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) async => null;

  @override
  AiTranscriptAdapter get adapter => const AntigravityAiTranscriptAdapter();

  @override
  AiTranscriptLineAppend? get lineAppend => null;

  @override
  AiTranscriptPageReader? get pageReader => null;

  @override
  Future<String?> resolveParentTranscriptPath(SessionHistoryContext ctx) =>
      Future.value();

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) => Future.value();

  @override
  AiTranscriptIncrementalRefresher? get incrementalRefresher => null;

  @override
  String get tailFallbackPrefix => 'antigravity';

  @override
  Set<String> get subagentToolNames => const {'invoke_subagent'};

  @override
  SubagentSideResolver get subagentSideResolver =>
      const NullSubagentSideResolver();

  @override
  ToolResultEnricher get toolResultEnricher => const NoOpToolResultEnricher();

  /// Antigravity's isolated home is the session tool root; `~/.gemini` is
  /// derived from it by the CLI, so history only needs `HOME`.
  @override
  Map<String, String> sessionEnv({String? toolRoot}) {
    if (toolRoot == null || toolRoot.isEmpty) return const {};
    return {'HOME': toolRoot};
  }

  @override
  ResumeBinding get binding => ResumeBinding.postCaptured;

  @override
  Future<String?> detectNativeId(ResumeContext ctx) async => null;

  @override
  AiEditToolTargetResolver get editResolver => _resolvers.editResolver;

  @override
  AiToolFileTargetResolver get fileResolver => _resolvers.fileResolver;

  @override
  AiShellToolTargetResolver get shellResolver => _resolvers.shellResolver;

  @override
  AiToolCallCategoryResolver get categoryResolver =>
      _resolvers.categoryResolver;
}

/// Parses nothing: Antigravity transcripts are surfaced via ACP, not the
/// CLI-native brain JSONL.
final class AntigravityAiTranscriptAdapter implements AiTranscriptAdapter {
  const AntigravityAiTranscriptAdapter();

  @override
  String get id => 'antigravity';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async => const [];
}
