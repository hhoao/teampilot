import 'package:ai_message_core/ai_message_core.dart';

import '../../../../chat/conversation/history/session_history_context.dart';
import '../../../registry/capabilities/ai_history_capability.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';
import '../../../registry/capabilities/shared_tool_call_resolvers.dart';
import '../../grok_constants.dart';

/// Grok history: the ACP runtime owns transcript extraction, so `locate`
/// returns null and the adapter parses nothing. Native `~/.grok/sessions`
/// history is not imported in this phase.
final class GrokAiHistoryCapability implements AiHistoryCapability {
  const GrokAiHistoryCapability();

  static const _resolvers = SharedToolCallResolvers();

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) async => null;

  @override
  AiTranscriptAdapter get adapter => const GrokAiTranscriptAdapter();

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
  String get tailFallbackPrefix => GrokConstants.executableName;

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
    return {GrokConstants.homeEnvKey: toolRoot};
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

/// Parses nothing: Grok transcripts are surfaced via ACP, not a native JSONL
/// file imported by TeamPilot.
final class GrokAiTranscriptAdapter implements AiTranscriptAdapter {
  const GrokAiTranscriptAdapter();

  @override
  String get id => GrokConstants.executableName;

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async => const [];
}
