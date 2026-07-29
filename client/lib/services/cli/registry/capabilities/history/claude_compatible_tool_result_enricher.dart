import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import '../../../../../utils/logging/logger.dart';
import '../../../../session/session_history_context.dart';
import 'tool_result_enricher.dart';

const _truncationSentinel = 'tool output truncated';

final class ClaudeCompatibleToolResultEnricher implements ToolResultEnricher {
  const ClaudeCompatibleToolResultEnricher();

  @override
  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    required SessionHistoryContext ctx,
    required String? rootTranscriptPath,
    required AiTranscriptBundle? bundle,
  }) async {
    try {
      final content = await _loadTranscriptContent(
        ctx: ctx,
        rootTranscriptPath: rootTranscriptPath,
        bundle: bundle,
      );
      if (content == null || content.trim().isEmpty) return messages;

      final toolUseResults = _indexToolUseResults(content);
      if (toolUseResults.isEmpty) return messages;

      final updated = List<AiMessage>.from(messages);
      for (var i = 0; i < updated.length; i++) {
        final message = updated[i];
        final parts = List<AiMessagePart>.from(message.parts);
        var changed = false;

        for (var j = 0; j < parts.length; j++) {
          final part = parts[j];
          if (part is! AiToolCallPart || !_isTruncated(part.result)) continue;

          final side = toolUseResults[part.toolCallId];
          if (side == null) continue;

          final replacement = _replacementFromToolUseResult(side.toolUseResult);
          if (replacement == null) continue;

          parts[j] = part.copyWith(
            result: replacement.text,
            status: AiToolCallStatus.complete,
            isError: replacement.isError || part.isError || side.blockIsError,
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
        '[tool-result-enricher] Claude-compatible enrich failed '
        'path=${rootTranscriptPath ?? (bundle?.fragments.isNotEmpty == true ? bundle!.fragments.first.name : null)}: $e',
        error: e,
        stackTrace: st,
      );
      return messages;
    }
  }
}

final class _IndexedToolUseResult {
  const _IndexedToolUseResult({
    required this.toolUseResult,
    required this.blockIsError,
  });

  final Object? toolUseResult;
  final bool blockIsError;
}

final class _Replacement {
  const _Replacement({required this.text, required this.isError});

  final String text;
  final bool isError;
}

Future<String?> _loadTranscriptContent({
  required SessionHistoryContext ctx,
  required String? rootTranscriptPath,
  required AiTranscriptBundle? bundle,
}) async {
  if (bundle != null && bundle.fragments.isNotEmpty) {
    final buffer = StringBuffer();
    for (final fragment in bundle.fragments) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(utf8.decode(fragment.bytes, allowMalformed: true));
    }
    return buffer.toString();
  }

  final path = rootTranscriptPath?.trim();
  if (path == null || path.isEmpty) return null;

  final bytes = await ctx.fs.readBytes(path);
  if (bytes == null) return null;
  return utf8.decode(bytes, allowMalformed: true);
}

Map<String, _IndexedToolUseResult> _indexToolUseResults(String content) {
  final index = <String, _IndexedToolUseResult>{};
  for (final line in const LineSplitter().convert(content)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    final event = _tryDecodeObject(trimmed);
    if (event == null) continue;
    if (event['type'] != 'user') continue;

    final toolUseResult = event['toolUseResult'];
    if (toolUseResult == null) continue;

    final message = event['message'];
    if (message is! Map) continue;
    final blocks = message['content'];
    if (blocks is! List) continue;

    for (final block in blocks) {
      if (block is! Map) continue;
      if (block['type'] != 'tool_result') continue;

      final toolUseId = block['tool_use_id'];
      if (toolUseId is! String || toolUseId.isEmpty) continue;

      index[toolUseId] = _IndexedToolUseResult(
        toolUseResult: toolUseResult,
        blockIsError: block['is_error'] == true,
      );
    }
  }
  return index;
}

Map<String, dynamic>? _tryDecodeObject(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on FormatException {
    return null;
  }
  return null;
}

bool _isTruncated(Object? result) {
  if (result == null) return false;
  final text = result is String ? result : result.toString();
  return text.toLowerCase().contains(_truncationSentinel);
}

_Replacement? _replacementFromToolUseResult(Object? toolUseResult) {
  if (toolUseResult is String) {
    final text = toolUseResult.trim();
    if (text.isEmpty) return null;
    return _Replacement(text: text, isError: false);
  }

  if (toolUseResult is Map) {
    final map = Map<String, dynamic>.from(toolUseResult);
    final stdout = _stringValue(map['stdout']);
    final stderr = _stringValue(map['stderr']);
    final text = _combineStdoutStderr(stdout, stderr);
    if (text.isEmpty) return null;

    return _Replacement(
      text: text,
      isError: _isErrorExitCode(map['exitCode']),
    );
  }

  return null;
}

String _stringValue(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return '$value';
}

String _combineStdoutStderr(String stdout, String stderr) {
  if (stderr.trim().isEmpty) return stdout;
  if (stdout.trim().isEmpty) return stderr;
  return '$stdout\n$stderr';
}

bool _isErrorExitCode(Object? exitCode) {
  if (exitCode is int) return exitCode != 0;
  if (exitCode is num) return exitCode.toInt() != 0;
  return false;
}
