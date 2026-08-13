import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import 'package:logger/logger.dart';
import '../../../../../utils/logging/logger.dart';
import '../../../../io/filesystem.dart';
import '../../../../session/session_history_context.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';

/// opencode core-truncation marker: `...N bytes truncated...` /
/// `...N lines truncated...` (see opencode `tool/truncate.ts`). Deliberately
/// does not match tool-internal windowing (read `line truncated to N chars`,
/// grep `Results truncated`) which has no on-disk copy to backfill from.
final RegExp opencodeCoreTruncationMarker = RegExp(
  r'\.\.\.\d+ (?:bytes|lines) truncated\.\.\.',
);

/// Hint line embedded in the truncation placeholder; the full output lives at
/// the captured absolute path (`<data>/tool-output/tool_<id>`).
final _savedToHint = RegExp(r'Full output saved to:\s*(\S+)');

/// Backfills opencode tool parts whose result carries the core-truncation
/// placeholder by reading the full output file referenced by the
/// `Full output saved to:` hint.
///
/// Keeps the placeholder untouched when the file is missing or unreadable
/// (opencode retains truncated outputs for 7 days, then the hint path may be
/// gone) and when the result carries no hint — mirroring
/// [ClaudeCompatibleToolResultEnricher]'s fail-open semantics.
final class OpencodeToolOutputBackfillEnricher implements ToolResultEnricher {
  const OpencodeToolOutputBackfillEnricher();

  @override
  bool get requiresFilesystem => true;

  @override
  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    required SessionHistoryContext? ctx,
    required String? rootTranscriptPath,
    required AiTranscriptBundle? bundle,
  }) async {
    final fs = ctx?.fs;
    if (fs == null) return messages;

    try {
      final updated = List<AiMessage>.from(messages);
      for (var i = 0; i < updated.length; i++) {
        final message = updated[i];
        final parts = List<AiMessagePart>.from(message.parts);
        var changed = false;

        for (var j = 0; j < parts.length; j++) {
          final part = parts[j];
          if (part is! AiToolCallPart) continue;

          final full = await _readFullOutput(part.result, fs);
          if (full == null) continue;

          parts[j] = part.copyWith(
            result: full,
            status: AiToolCallStatus.complete,
          );
          changed = true;
        }

        if (changed) {
          updated[i] = message.copyWith(parts: parts);
        }
      }
      return updated;
    } catch (e, st) {
      appLogger.w(
        '[tool-result-enricher] opencode output backfill failed: $e',
        error: e,
        stackTrace: st,
      );
      return messages;
    }
  }
}

Future<String?> _readFullOutput(Object? result, Filesystem fs) async {
  if (result is! String) return null;
  if (!opencodeCoreTruncationMarker.hasMatch(result)) return null;

  final match = _savedToHint.firstMatch(result);
  final path = match?.group(1)?.trim();
  if (path == null || path.isEmpty) return null;

  final bytes = await fs.readBytes(path);
  if (bytes == null || bytes.isEmpty) return null;

  final text = utf8.decode(bytes, allowMalformed: true);
  if (text.trim().isEmpty) return null;
  return text;
}
