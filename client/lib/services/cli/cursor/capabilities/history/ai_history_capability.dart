import 'package:ai_message_core/ai_message_core.dart';

import '../../../registry/capabilities/ai_history_capability.dart';
import '../../../../session/session_history_context.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';
import 'ai_transcript.dart';
import 'side_resolver.dart';
import 'terminal_tool_result_enricher.dart';

final class CursorAiHistoryCapability implements AiHistoryCapability {
  const CursorAiHistoryCapability({
    required this.shellResolver,
    this.subagentSideResolver = const CursorSideResolver(),
  });

  final AiShellToolTargetResolver shellResolver;

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateCursorTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const CursorAiTranscriptAdapter();

  @override
  AiTranscriptLineAppend get lineAppend => appendCursorJsonlEvent;

  @override
  String get tailFallbackPrefix => 'cursor';

  @override
  Set<String> get subagentToolNames => const {'agent', 'task'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  ToolResultEnricher get toolResultEnricher => CursorTerminalToolResultEnricher(
        shellResolver: shellResolver,
      );

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) async => null;
}
