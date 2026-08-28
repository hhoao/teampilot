import 'package:ai_message_core/ai_message_core.dart';

import '../../../../session/session_history_context.dart';

abstract interface class ToolResultEnricher {
  /// True when [result] carries this enricher's truncation marker — a
  /// placeholder the enricher could backfill. The loader's enrichment guard
  /// consults this to skip [enrich] when no part needs it; enrichers that
  /// backfill non-marker shapes (e.g. missing results) return false.
  bool matchesTruncationMarker(String result) => false;

  /// Part 级门控谓词:loader 在调用 [enrich] 前用它判断是否有需要该
  /// enricher 的 part。默认实现保持历史门控语义(String result 且命中
  /// 截断 marker);回填非 marker 形状(如缺失 result)的 enricher 覆写。
  bool needsEnrichment(AiToolCallPart part) =>
      defaultToolResultNeedsEnrichment(this, part);

  /// True when [enrich] touches the filesystem via [SessionHistoryContext].
  ///
  /// Enrichers that only work on the already-read [AiTranscriptBundle] can be
  /// invoked inside the loader's worker isolate together with the parse (see
  /// [AiHistoryLoader]); filesystem-backed enrichers must stay on the caller
  /// isolate where [ctx] is available.
  bool get requiresFilesystem => true;

  /// [ctx] is null when running on the loader worker isolate; enrichers must
  /// not touch the filesystem in that case (guarded by [requiresFilesystem]).
  ///
  /// [sourceToken] is the loader's transcript identity token (path + version
  /// and size). Cache-aware enrichers key their index by identity and use size
  /// to reuse, append, or rebuild.
  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    required SessionHistoryContext? ctx,
    required String? rootTranscriptPath,
    required AiTranscriptBundle? bundle,
    String? sourceToken,
  });
}

/// Optional in-memory tool-result index. Implemented by cache-aware enrichers
/// so the loader can reuse, append, invalidate, and round-trip isolate work.
abstract interface class ToolResultIndexCache {
  /// Drops a cached index. Null [sourceToken] clears every entry.
  void invalidateIndex({String? sourceToken});

  /// True when [ToolResultEnricher.enrich] can apply replacements without
  /// decoding [contentLength] bytes of the identified transcript.
  bool canReuseIndex({String? sourceToken, required int contentLength});

  /// Isolate-transfer snapshot of the in-memory index.
  Object? exportIndex();

  /// Installs an index produced on a worker isolate onto this instance.
  void importIndex(Object? snapshot);
}

/// Canonical marker-shape gate shared by the interface default and marker-only
/// enrichers: a String result carrying this enricher's truncation marker.
bool defaultToolResultNeedsEnrichment(
  ToolResultEnricher enricher,
  AiToolCallPart part,
) {
  final result = part.result;
  return result is String && enricher.matchesTruncationMarker(result);
}

final class NoOpToolResultEnricher implements ToolResultEnricher {
  const NoOpToolResultEnricher();

  @override
  bool get requiresFilesystem => false;

  @override
  bool matchesTruncationMarker(String result) => false;

  @override
  bool needsEnrichment(AiToolCallPart part) =>
      defaultToolResultNeedsEnrichment(this, part);

  @override
  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    required SessionHistoryContext? ctx,
    required String? rootTranscriptPath,
    required AiTranscriptBundle? bundle,
    String? sourceToken,
  }) async =>
      messages;
}
