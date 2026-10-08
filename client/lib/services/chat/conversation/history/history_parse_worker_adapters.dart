import 'package:ai_message_core/ai_message_core.dart';

import '../../../cli/claude/capabilities/history/ai_transcript.dart';
import '../../../cli/claude/capabilities/history/compatible_tool_result_enricher.dart';
import '../../../cli/codex/capabilities/history/ai_transcript.dart';
import '../../../cli/cursor/capabilities/history/ai_transcript.dart';
import '../../../cli/flashskyai/capabilities/history/ai_transcript.dart';
import '../../../cli/opencode/capabilities/history/ai_transcript.dart';
import 'history_parse_worker.dart';

/// Parses a transcript bundle with a built-in adapter safe to construct in a
/// history worker isolate.
Future<HistoryParseResult> parseHistoryBundleInWorker({
  required String adapterId,
  required AiTranscriptBundle bundle,
  String? workerEnricherId,
  String? sourceToken,
  String? rootTranscriptPath,
}) async {
  final adapter = switch (adapterId) {
    'claude' => const ClaudeAiTranscriptAdapter(),
    'codex' => const CodexAiTranscriptAdapter(),
    'cursor' => const CursorAiTranscriptAdapter(),
    'flashskyai' => const FlashskyaiAiTranscriptAdapter(),
    'opencode' => const OpencodeAiTranscriptAdapter(),
    _ => throw UnsupportedError('No history worker adapter for "$adapterId"'),
  };

  final parseSw = Stopwatch()..start();
  final messages = await adapter.parse(bundle);
  parseSw.stop();

  if (workerEnricherId == 'claude-compatible') {
    final enrichSw = Stopwatch()..start();
    final enricher = ClaudeCompatibleToolResultEnricher();
    if (!_needsToolResultEnrichment(messages, enricher)) {
      enrichSw.stop();
      return HistoryParseResult(messages: messages, parseTime: parseSw.elapsed);
    }
    final enriched = await enricher.enrich(
      messages: messages,
      ctx: null,
      rootTranscriptPath: rootTranscriptPath,
      bundle: bundle,
      sourceToken: sourceToken,
    );
    enrichSw.stop();
    return HistoryParseResult(
      messages: enriched,
      indexSnapshot: enricher.exportIndex(),
      parseTime: parseSw.elapsed,
      enrichTime: enrichSw.elapsed,
    );
  }

  return HistoryParseResult(messages: messages, parseTime: parseSw.elapsed);
}

bool _needsToolResultEnrichment(
  List<AiMessage> messages,
  ClaudeCompatibleToolResultEnricher enricher,
) {
  for (final message in messages) {
    for (final part in message.parts) {
      if (part is AiToolCallPart && enricher.needsEnrichment(part)) {
        return true;
      }
    }
  }
  return false;
}
