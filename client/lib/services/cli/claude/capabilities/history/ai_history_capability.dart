import 'package:ai_message_core/ai_message_core.dart';

import '../../../registry/capabilities/ai_history_capability.dart';
import '../../../../session/session_history_context.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';
import 'ai_transcript.dart';
import 'compatible_jsonl.dart';
import 'compatible_tool_result_enricher.dart';
import 'side_resolver.dart';

final class ClaudeAiHistoryCapability implements AiHistoryCapability {
  const ClaudeAiHistoryCapability({
    this.subagentSideResolver = const ClaudeSideResolver(),
    this.toolResultEnricher = const ClaudeCompatibleToolResultEnricher(),
  });

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateClaudeTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const ClaudeAiTranscriptAdapter();

  @override
  AiTranscriptLineAppend get lineAppend => appendClaudeJsonlEvent;

  @override
  String get tailFallbackPrefix => 'claude';

  @override
  Set<String> get subagentToolNames => const {'agent', 'task', 'workflow'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  final ToolResultEnricher toolResultEnricher;

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) async => null;
}
