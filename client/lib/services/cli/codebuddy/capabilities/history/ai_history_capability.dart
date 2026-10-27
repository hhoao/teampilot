import 'package:ai_message_core/ai_message_core.dart';

import '../../../../chat/conversation/history/session_history_context.dart';
import '../../../registry/capabilities/ai_history_capability.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';
import '../../../registry/capabilities/shared_tool_call_resolvers.dart';

/// CodeBuddy history: ACP sessions own their transcript
/// (`acp-transcript.jsonl`), so this adapter never locates or parses the
/// CLI-native `~/.codebuddy/projects/*.jsonl` transcript. `session/load` is
/// never called either.
final class CodebuddyAiHistoryCapability implements AiHistoryCapability {
  const CodebuddyAiHistoryCapability();

  static const _resolvers = SharedToolCallResolvers();

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) async => null;

  @override
  AiTranscriptAdapter get adapter => const CodebuddyAiTranscriptAdapter();

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
  String get tailFallbackPrefix => 'codebuddy';

  @override
  Set<String> get subagentToolNames => const {};

  @override
  SubagentSideResolver get subagentSideResolver =>
      const NullSubagentSideResolver();

  @override
  ToolResultEnricher get toolResultEnricher => const NoOpToolResultEnricher();

  @override
  Map<String, String> sessionEnv({String? toolRoot}) {
    if (toolRoot == null || toolRoot.isEmpty) return const {};
    return {'CODEBUDDY_CONFIG_DIR': toolRoot};
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

/// Parses nothing: CodeBuddy transcripts are surfaced via ACP, not JSONL.
final class CodebuddyAiTranscriptAdapter implements AiTranscriptAdapter {
  const CodebuddyAiTranscriptAdapter();

  @override
  String get id => 'codebuddy';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async => const [];
}
