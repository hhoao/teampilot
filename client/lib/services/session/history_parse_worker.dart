import 'package:ai_message_core/ai_message_core.dart';

/// Result returned by a worker-safe transcript parse and optional enrichment.
final class HistoryParseResult {
  const HistoryParseResult({
    required this.messages,
    this.indexSnapshot,
    this.parseTime = Duration.zero,
    this.enrichTime = Duration.zero,
  });

  final List<AiMessage> messages;
  final Object? indexSnapshot;
  final Duration parseTime;
  final Duration enrichTime;
}

/// Boundary for transcript parsing performed away from the caller isolate.
abstract interface class HistoryParseExecutor {
  Future<HistoryParseResult> parse({
    required String adapterId,
    required AiTranscriptBundle bundle,
    String? workerEnricherId,
    String? sourceToken,
    String? rootTranscriptPath,
  });

  Future<void> dispose();
}
