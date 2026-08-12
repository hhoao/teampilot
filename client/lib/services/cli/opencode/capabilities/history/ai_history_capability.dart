import 'package:ai_message_core/ai_message_core.dart';

import '../../../registry/capabilities/ai_history_capability.dart';
import '../../../../session/session_history_context.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';
import 'ai_transcript.dart';
import 'side_resolver.dart';

final class OpencodeAiHistoryCapability
    implements AiHistoryCapability, AiTranscriptIncrementalCapability {
  const OpencodeAiHistoryCapability({
    this.subagentSideResolver = const OpencodeSideResolver(),
    this.toolResultEnricher = const NoOpToolResultEnricher(),
    this.liveCacheTokenImpl = opencodeLiveCacheToken,
  });

  final Future<String?> Function(SessionHistoryContext ctx) liveCacheTokenImpl;

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateOpencodeTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const OpencodeAiTranscriptAdapter();

  @override
  AiTranscriptLineAppend? get lineAppend => null; // multi-file DB; no single-line incremental dialect.

  @override
  AiTranscriptIncrementalRefresher get incrementalRefresher =>
      const OpencodeHistoryIncrementalRefresher();

  @override
  String get tailFallbackPrefix => 'opencode';

  @override
  Set<String> get subagentToolNames => const {'task'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  final ToolResultEnricher toolResultEnricher;

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) =>
      liveCacheTokenImpl(ctx);
}
