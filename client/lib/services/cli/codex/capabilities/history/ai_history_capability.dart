import 'package:ai_message_core/ai_message_core.dart';

import '../../../registry/capabilities/ai_history_capability.dart';
import '../../../../session/session_history_context.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';
import 'ai_transcript.dart';
import 'side_resolver.dart';

final class CodexAiHistoryCapability implements AiHistoryCapability {
  const CodexAiHistoryCapability({
    this.subagentSideResolver = const CodexSideResolver(),
    this.toolResultEnricher = const NoOpToolResultEnricher(),
  });

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateCodexTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const CodexAiTranscriptAdapter();

  @override
  AiTranscriptLineAppend get lineAppend => appendCodexJsonlEvent;

  @override
  String get tailFallbackPrefix => 'codex';

  @override
  Set<String> get subagentToolNames => const {'spawn_agent', 'agent', 'task'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  final ToolResultEnricher toolResultEnricher;

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) async => null;
}
