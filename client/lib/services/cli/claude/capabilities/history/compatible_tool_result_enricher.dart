import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import '../../../../../utils/logging/logger.dart';
import '../../../../session/session_history_context.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';

const _truncationSentinel = 'tool output truncated';

/// Decodes JSONL object lines for the tool-result index. Tests inject a
/// counter; production uses [jsonDecode] per non-empty line.
typedef ToolResultLineDecoder =
    List<Map<String, dynamic>?> Function(List<String> lines);

final class ClaudeCompatibleToolResultEnricher
    implements ToolResultEnricher, ToolResultIndexCache {
  ClaudeCompatibleToolResultEnricher({ToolResultLineDecoder? decodeLines})
    : _decodeLines = decodeLines ?? _defaultDecodeLines;

  final ToolResultLineDecoder _decodeLines;
  final Map<String, _CachedToolResultIndex> _indexes = {};

  @override
  bool get requiresFilesystem => false;

  @override
  bool matchesTruncationMarker(String result) => _isTruncated(result);

  @override
  bool needsEnrichment(AiToolCallPart part) =>
      defaultToolResultNeedsEnrichment(this, part);

  @override
  void invalidateIndex({String? sourceToken}) {
    if (sourceToken == null) {
      _indexes.clear();
      return;
    }
    final token = sourceToken.trim();
    if (token.isEmpty) return;
    _indexes.remove(_identityFromToken(token));
    _indexes.remove(token);
  }

  @override
  bool canReuseIndex({String? sourceToken, required int contentLength}) {
    final identity = _identityFromToken(sourceToken ?? '');
    if (identity.isEmpty) return false;
    final cached = _indexes[identity];
    return cached != null &&
        (cached.indexedLength == contentLength ||
            cached.indexedBytes == contentLength);
  }

  @override
  Object? exportIndex() {
    if (_indexes.isEmpty) return null;
    return {
      for (final entry in _indexes.entries)
        entry.key: {
          'indexedLength': entry.value.indexedLength,
          'indexedBytes': entry.value.indexedBytes,
          'boundary': entry.value.boundary,
          'records': {
            for (final record in entry.value.records.entries)
              record.key: {
                'toolUseResult': record.value.toolUseResult,
                'blockIsError': record.value.blockIsError,
              },
          },
        },
    };
  }

  @override
  void importIndex(Object? snapshot) {
    if (snapshot is! Map) return;
    for (final entry in snapshot.entries) {
      final identity = entry.key;
      final value = entry.value;
      if (identity is! String || identity.isEmpty || value is! Map) continue;
      final indexedLength = value['indexedLength'];
      final indexedBytes = value['indexedBytes'];
      final boundary = value['boundary'];
      final rawRecords = value['records'];
      if (indexedLength is! int ||
          boundary is! String ||
          rawRecords is! Map) {
        continue;
      }
      final records = <String, _IndexedToolUseResult>{};
      for (final record in rawRecords.entries) {
        final id = record.key;
        final payload = record.value;
        if (id is! String || payload is! Map) continue;
        records[id] = _IndexedToolUseResult(
          toolUseResult: payload['toolUseResult'],
          blockIsError: payload['blockIsError'] == true,
        );
      }
      _indexes[identity] = _CachedToolResultIndex(
        indexedLength: indexedLength,
        indexedBytes: indexedBytes is int ? indexedBytes : indexedLength,
        boundary: boundary,
        records: records,
      );
    }
  }

  @override
  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    required SessionHistoryContext? ctx,
    required String? rootTranscriptPath,
    required AiTranscriptBundle? bundle,
    String? sourceToken,
  }) async {
    try {
      final content = await _loadTranscriptContent(
        ctx: ctx,
        rootTranscriptPath: rootTranscriptPath,
        bundle: bundle,
      );
      if (content == null || content.trim().isEmpty) return messages;

      final identity = _cacheIdentity(
        sourceToken: sourceToken,
        rootTranscriptPath: rootTranscriptPath,
        bundle: bundle,
      );
      final toolUseResults = _recordsFor(identity: identity, content: content);
      if (toolUseResults.isEmpty) return messages;

      return _applyIndex(messages, toolUseResults);
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

  Map<String, _IndexedToolUseResult> _recordsFor({
    required String identity,
    required String content,
  }) {
    final length = content.length;
    final cached = identity.isEmpty ? null : _indexes[identity];
    if (cached != null &&
        cached.indexedLength == length &&
        cached.boundary == _boundaryOf(content, length)) {
      return cached.records;
    }
    if (cached != null &&
        length > cached.indexedLength &&
        _boundaryOf(content, cached.indexedLength) == cached.boundary) {
      final appended = _indexToolUseResults(
        content.substring(cached.indexedLength),
      );
      final merged = {...cached.records, ...appended};
      _storeIndex(
        identity: identity,
        content: content,
        records: merged,
      );
      return merged;
    }
    final records = _indexToolUseResults(content);
    _storeIndex(identity: identity, content: content, records: records);
    return records;
  }

  void _storeIndex({
    required String identity,
    required String content,
    required Map<String, _IndexedToolUseResult> records,
  }) {
    if (identity.isEmpty) return;
    _indexes[identity] = _CachedToolResultIndex(
      indexedLength: content.length,
      indexedBytes: utf8.encode(content).length,
      boundary: _boundaryOf(content, content.length),
      records: records,
    );
  }

  Map<String, _IndexedToolUseResult> _indexToolUseResults(String content) {
    final lines = <String>[];
    for (final line in const LineSplitter().convert(content)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      lines.add(trimmed);
    }
    if (lines.isEmpty) return const {};
    return _indexDecodedEvents(_decodeLines(lines));
  }
}

final class _CachedToolResultIndex {
  const _CachedToolResultIndex({
    required this.indexedLength,
    required this.indexedBytes,
    required this.boundary,
    required this.records,
  });

  final int indexedLength;
  final int indexedBytes;
  final String boundary;
  final Map<String, _IndexedToolUseResult> records;
}

String _cacheIdentity({
  required String? sourceToken,
  required String? rootTranscriptPath,
  required AiTranscriptBundle? bundle,
}) {
  final path = rootTranscriptPath?.trim();
  if (path != null && path.isNotEmpty) return path;
  final token = sourceToken?.trim();
  if (token != null && token.isNotEmpty) return _identityFromToken(token);
  if (bundle != null && bundle.fragments.isNotEmpty) {
    return bundle.fragments.map((f) => f.name).join('\n');
  }
  return '';
}

String _identityFromToken(String token) {
  final parts = token.split('|');
  if (parts.length >= 3 && int.tryParse(parts.last) != null) {
    return parts.sublist(0, parts.length - 2).join('|');
  }
  return token;
}

String _boundaryOf(String content, int length) {
  final end = length < 0
      ? 0
      : (length > content.length ? content.length : length);
  final start = end > 64 ? end - 64 : 0;
  return content.substring(start, end);
}

List<AiMessage> _applyIndex(
  List<AiMessage> messages,
  Map<String, _IndexedToolUseResult> toolUseResults,
) {
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
  required SessionHistoryContext? ctx,
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
  final fs = ctx?.fs;
  if (fs == null) return null;

  final bytes = await fs.readBytes(path);
  if (bytes == null) return null;
  return utf8.decode(bytes, allowMalformed: true);
}

Map<String, _IndexedToolUseResult> _indexDecodedEvents(
  List<Map<String, dynamic>?> events,
) {
  final index = <String, _IndexedToolUseResult>{};
  for (final event in events) {
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

List<Map<String, dynamic>?> _defaultDecodeLines(List<String> lines) =>
    [for (final line in lines) _tryDecodeObject(line)];

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
