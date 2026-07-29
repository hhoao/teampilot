import 'package:ai_message_core/ai_message_core.dart';

import '../../../../session/session_history_context.dart';

abstract interface class ToolResultEnricher {
  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    required SessionHistoryContext ctx,
    required String? rootTranscriptPath,
    required AiTranscriptBundle? bundle,
  });
}

final class NoOpToolResultEnricher implements ToolResultEnricher {
  const NoOpToolResultEnricher();

  @override
  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    required SessionHistoryContext ctx,
    required String? rootTranscriptPath,
    required AiTranscriptBundle? bundle,
  }) async =>
      messages;
}
