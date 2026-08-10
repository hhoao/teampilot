import 'package:ai_message_core/ai_message_core.dart';

import '../../../../session/session_history_context.dart';

abstract interface class ToolResultEnricher {
  /// True when [enrich] touches the filesystem via [SessionHistoryContext].
  ///
  /// Enrichers that only work on the already-read [AiTranscriptBundle] can be
  /// invoked inside the loader's worker isolate together with the parse (see
  /// [AiHistoryLoader]); filesystem-backed enrichers must stay on the caller
  /// isolate where [ctx] is available.
  bool get requiresFilesystem => true;

  /// [ctx] is null when running on the loader worker isolate; enrichers must
  /// not touch the filesystem in that case (guarded by [requiresFilesystem]).
  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    required SessionHistoryContext? ctx,
    required String? rootTranscriptPath,
    required AiTranscriptBundle? bundle,
  });
}

final class NoOpToolResultEnricher implements ToolResultEnricher {
  const NoOpToolResultEnricher();

  @override
  bool get requiresFilesystem => false;

  @override
  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    required SessionHistoryContext? ctx,
    required String? rootTranscriptPath,
    required AiTranscriptBundle? bundle,
  }) async =>
      messages;
}
