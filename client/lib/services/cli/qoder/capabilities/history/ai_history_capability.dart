import 'package:ai_message_core/ai_message_core.dart';

import '../../../../chat/conversation/history/session_history_context.dart';
import '../../../registry/capabilities/ai_history_capability.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';
import '../../../registry/capabilities/shared_tool_call_resolvers.dart';
import '../../qoder_flavor.dart';

/// Qoder history: ACP sessions own their transcript
/// (`acp-transcript.jsonl`), so this adapter never locates or parses the
/// CLI-native `~/.qoder/projects/*.jsonl` transcript for history browsing.
/// `session/load` is never called either.
///
/// The native JSONL is still read by the ACP background watch
/// (`QoderAcpBackgroundTranscriptSource`), which only needs appended records
/// to notice that out-of-turn work finished.
final class QoderAiHistoryCapability implements AiHistoryCapability {
  const QoderAiHistoryCapability({this.flavor = QoderFlavor.global});

  final QoderFlavor flavor;

  static const _resolvers = SharedToolCallResolvers();

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) async => null;

  @override
  AiTranscriptAdapter get adapter =>
      QoderAiTranscriptAdapter(id: flavor.cli.value);

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
  String get tailFallbackPrefix => flavor.cli.value;

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
    return {flavor.configDirEnvKey: toolRoot};
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

/// Parses nothing: Qoder transcripts are surfaced via ACP, not JSONL.
final class QoderAiTranscriptAdapter implements AiTranscriptAdapter {
  const QoderAiTranscriptAdapter({this.id = 'qoder'});

  @override
  final String id;

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async => const [];
}
