import 'package:ai_message_core/ai_message_core.dart';

import '../../../registry/capabilities/ai_history_capability.dart';
import '../../../../session/session_history_context.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';
import '../../../claude/capabilities/history/compatible_jsonl.dart';
import '../../../claude/capabilities/history/compatible_side_resolver.dart';
import '../../../claude/capabilities/history/compatible_tool_result_enricher.dart';
import 'ai_transcript.dart';

final class FlashskyaiAiHistoryCapability implements AiHistoryCapability {
  const FlashskyaiAiHistoryCapability({
    this.subagentSideResolver = const ClaudeCompatibleSideResolver(),
    this.toolResultEnricher = const ClaudeCompatibleToolResultEnricher(),
  });

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateFlashskyaiTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const FlashskyaiAiTranscriptAdapter();

  @override
  AiTranscriptLineAppend get lineAppend => appendClaudeJsonlEvent;

  @override
  String get tailFallbackPrefix => 'flashskyai';

  @override
  Set<String> get subagentToolNames => const {'agent', 'task'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  final ToolResultEnricher toolResultEnricher;

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) async => null;
}
