import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import '../cli/registry/capabilities/ai_history_capability.dart';
import '../io/filesystem.dart';
import 'ai_history_page.dart';
import 'ai_transcript_tail_reader.dart';
import 'jsonl_decode_worker.dart';
import 'session_history_context.dart';

typedef AiTranscriptSourcePath =
    Future<String?> Function(SessionHistoryContext ctx);
typedef AiTranscriptSourceVersion =
    Future<String?> Function(String path, FsStat stat);

/// Complete-line JSONL page source. It refuses suffix fallback ids because
/// their sequence cannot be proven equivalent without parsing the prefix.
final class JsonlTranscriptPageReader implements AiTranscriptPageReader {
  JsonlTranscriptPageReader({
    this.fs,
    required AiTranscriptLineAppend lineAppend,
    required String fallbackPrefix,
    required AiTranscriptSourcePath sourcePath,
    AiTranscriptSourceVersion? sourceVersion,
    EventDecoder? decodeEvents,
    this.windowSizes = const [256 * 1024, 1024 * 1024],
  }) : _lineAppend = lineAppend,
       _fallbackPrefix = fallbackPrefix,
       _decodeEvents = decodeEvents ?? decodeJsonlLines,
       _sourcePath = sourcePath,
       _sourceVersion = sourceVersion ?? _highPrecisionStatVersion;

  /// Test override. Production reads go through [SessionHistoryContext.fs].
  final Filesystem? fs;

  Filesystem _boundFs(SessionHistoryContext ctx) => fs ?? ctx.fs;
  final AiTranscriptLineAppend _lineAppend;
  final String _fallbackPrefix;
  final EventDecoder _decodeEvents;
  final AiTranscriptSourcePath _sourcePath;
  final AiTranscriptSourceVersion _sourceVersion;
  final List<int> windowSizes;

  @override
  Future<AiHistoryPage?> readLatest({
    required SessionHistoryContext ctx,
    required int limit,
  }) async {
    if (limit <= 0) return null;
    final path = await _sourcePath(ctx);
    if (path == null || path.isEmpty) return null;
    final filesystem = _boundFs(ctx);
    final stat = await filesystem.stat(path);
    if (!stat.isFile) return null;
    final size = stat.size ?? 0;
    final sourceToken = await _sourceToken(path, stat);
    if (sourceToken == null) return null;
    if (size == 0) return _emptyPage(sourceToken: sourceToken, rebuilt: true);

    for (final window in _windowsFor(size)) {
      final lines = await _readLatestLines(filesystem, path, size, window);
      final page = await _buildPage(
        lines,
        limit: limit,
        sourceToken: sourceToken,
        rebuilt: true,
      );
      // Unsafe suffix (orphan tool_result / fallback ids) → grow the window.
      // Only give up after the full-file window also fails.
      if (page == null) continue;
      if (page.messages.length >= limit || window >= size) return page;
    }
    return null;
  }

  @override
  Future<AiHistoryPage?> readOlder({
    required SessionHistoryContext ctx,
    required AiHistoryCursor cursor,
    required int limit,
  }) async {
    if (limit <= 0) return null;
    final path = await _sourcePath(ctx);
    if (path == null || path.isEmpty) return null;
    final filesystem = _boundFs(ctx);
    final stat = await filesystem.stat(path);
    if (!stat.isFile) return null;
    final size = stat.size ?? 0;
    final source = _decodeSourceToken(cursor.sourceToken);
    if (source == null || source.path != path || source.size != size)
      return null;
    final currentToken = await _sourceToken(path, stat);
    if (currentToken == null || currentToken != cursor.sourceToken) return null;
    if (cursor.offset <= 0 || cursor.offset > size) return null;
    final anchor = await _readLineAt(filesystem, path, cursor.offset, size);
    if (anchor == null || _lineHash(anchor.bytes) != cursor.lineHash) {
      return null;
    }

    for (final window in _windowsFor(cursor.offset)) {
      final lines = await _readOlderLines(
        filesystem,
        path,
        end: cursor.offset,
        window: window,
      );
      final page = await _buildPage(
        lines,
        limit: limit,
        sourceToken: cursor.sourceToken,
        rebuilt: false,
      );
      if (page == null) continue;
      if (page.messages.length >= limit || window >= cursor.offset) return page;
    }
    return null;
  }

  Iterable<int> _windowsFor(int size) sync* {
    for (final window in windowSizes) {
      if (window <= 0) continue;
      yield window;
      if (window >= size) return;
    }
    if (size > 0) yield size;
  }

  Future<AiHistoryPage?> _buildPage(
    List<_TranscriptLine> lines, {
    required int limit,
    required String sourceToken,
    required bool rebuilt,
  }) async {
    if (lines.isEmpty) {
      return _emptyPage(sourceToken: sourceToken, rebuilt: rebuilt);
    }
    final events = await _decodeEvents([for (final line in lines) line.bytes]);
    if (events.length != lines.length) return null;
    final parsed = _parseFrom(events, 0);
    final prefixComplete = lines.first.offset == 0;
    // Suffix windows: orphan tool_result / fallback ids cannot be proven.
    // Byte-0 windows match adapter.parse, including compaction leftovers
    // whose tool_use was removed — those orphans must not force a second
    // full-file decode via the loader fallback.
    if ((!prefixComplete && parsed.unresolvedDependency) ||
        _unsafeFallback(
          fallbackUsed: parsed.fallbackUsed,
          prefixComplete: prefixComplete,
        )) {
      return null;
    }
    // Ignore decoded noise and inspect the first event that the injected CLI
    // append semantics actually turns into a logical message. On a suffix
    // window, an assistant as the first consumed role may continue an omitted
    // fragment. On a byte-0 window, preamble lines (session_meta, etc.) make
    // the first message offset > 0 even when the transcript is complete.
    final firstConsumedIndex = parsed.firstConsumedIndex;
    if (!prefixComplete &&
        firstConsumedIndex != null &&
        parsed.firstConsumedRole == AiRole.assistant) {
      return null;
    }
    final rawStart = _rawStartIndex(
      parsed.messageCounts,
      parsed.messages.length,
      limit,
    );
    var contextStart = rawStart > 0 ? rawStart - 1 : rawStart;
    while (contextStart > 0) {
      final previousRole = parsed.consumedRoles[contextStart - 1];
      if (previousRole != null && previousRole != AiRole.assistant) break;
      contextStart--;
    }
    final contextual = _parseFrom(events, contextStart);
    if ((!prefixComplete && contextual.unresolvedDependency) ||
        _unsafeFallback(
          fallbackUsed: contextual.fallbackUsed,
          prefixComplete: prefixComplete,
        )) {
      return null;
    }
    final plain = contextStart == rawStart
        ? contextual
        : _parseFrom(events, rawStart);
    if ((!prefixComplete && plain.unresolvedDependency) ||
        _unsafeFallback(
          fallbackUsed: plain.fallbackUsed,
          prefixComplete: prefixComplete,
        )) {
      return null;
    }

    final completeMessages = prefixComplete
        ? finalizeAiMessagesForHistory(List<AiMessage>.of(parsed.messages))
        : null;
    final contextualMessages = finalizeAiMessagesForHistory(
      contextual.messages,
    );
    final plainMessages = finalizeAiMessagesForHistory(plain.messages);
    final contextualWindow = contextualMessages.length > limit
        ? contextualMessages.sublist(contextualMessages.length - limit)
        : contextualMessages;
    final needsContext =
        contextStart != rawStart &&
        !_sameMessages(contextualWindow, plainMessages);
    // Prefer the byte-0 finalize when available so first-paint ids match the
    // complete index (mid-slice fallback sequences renumber from zero).
    final output = completeMessages != null
        ? (completeMessages.length > limit
              ? completeMessages.sublist(completeMessages.length - limit)
              : completeMessages)
        : (contextualMessages.length > limit
              ? contextualMessages.sublist(contextualMessages.length - limit)
              : contextualMessages);
    final cursorLineIndex = needsContext ? contextStart : rawStart;
    final cursorLine = lines[cursorLineIndex];
    final hasOlder = cursorLine.offset > 0;
    return AiHistoryPage(
      messages: output,
      hasOlder: hasOlder,
      nextCursor: hasOlder
          ? AiHistoryCursor(
              sourceToken: sourceToken,
              offset: cursorLine.offset,
              lineHash: _lineHash(cursorLine.bytes),
            )
          : null,
      sourceToken: sourceToken,
      rebuilt: rebuilt,
      completeMessages: completeMessages,
    );
  }

  _ParsedLines _parseFrom(List<Map<String, dynamic>?> events, int start) {
    final messages = <AiMessage>[];
    final counts = <int>[];
    var fallbackSeq = 0;
    var fallbackUsed = false;
    var unresolvedDependency = false;
    int? firstConsumedIndex;
    AiRole? firstConsumedRole;
    final consumedRoles = <AiRole?>[];
    for (var i = start; i < events.length; i++) {
      final event = events[i];
      AiRole? consumedRole;
      if (event != null) {
        final before = fallbackSeq;
        final consumed = _lineAppend(
          messages,
          event,
          fallbackId: () {
            fallbackUsed = true;
            return '$_fallbackPrefix-${fallbackSeq++}';
          },
        );
        if (!consumed) fallbackSeq = before;
        if (consumed && firstConsumedIndex == null && messages.isNotEmpty) {
          firstConsumedIndex = i;
          firstConsumedRole = messages.last.role;
        }
        if (consumed && messages.isNotEmpty) consumedRole = messages.last.role;
        if (_containsToolResult(event) && !consumed) {
          unresolvedDependency = true;
        }
      }
      counts.add(messages.length);
      consumedRoles.add(consumedRole);
    }
    return _ParsedLines(
      messages: messages,
      messageCounts: counts,
      fallbackUsed: fallbackUsed,
      unresolvedDependency: unresolvedDependency,
      firstConsumedIndex: firstConsumedIndex,
      firstConsumedRole: firstConsumedRole,
      consumedRoles: consumedRoles,
    );
  }

  static bool _containsToolResult(Map<String, dynamic> event) {
    final message = event['message'];
    if (message is Map && _contentContainsToolResult(message['content'])) {
      return true;
    }
    final payload = event['payload'];
    if (payload is Map) {
      final type = payload['type'];
      return type == 'function_call_output' ||
          type == 'custom_tool_call_output' ||
          type == 'tool_result';
    }
    return false;
  }

  static bool _contentContainsToolResult(Object? content) {
    if (content is! List) return false;
    for (final block in content) {
      if (block is Map && block['type'] == 'tool_result') return true;
    }
    return false;
  }

  static bool _unsafeFallback({
    required bool fallbackUsed,
    required bool prefixComplete,
  }) {
    if (!fallbackUsed) return false;
    // Byte-0 windows already own the full prefix. Mid-slice fallback ids are
    // provisional for pagination cursors; [AiHistoryPage.completeMessages]
    // carries the adapter-equivalent full finalize for the loader.
    if (prefixComplete) return false;
    return true;
  }

  int _rawStartIndex(List<int> counts, int messageCount, int limit) {
    if (messageCount <= limit) return 0;
    final target = messageCount - limit;
    for (var i = 0; i < counts.length; i++) {
      if (counts[i] > target) return i;
    }
    return 0;
  }

  Future<List<_TranscriptLine>> _readLatestLines(
    Filesystem filesystem,
    String path,
    int size,
    int window,
  ) async {
    final start = size > window ? size - window : 0;
    // Include one extra window before the suffix so a streamed assistant
    // whose first visible fragment is at the boundary can be merged with its
    // preceding line without a second decode request.
    final readStart = start > 0 ? (start - window).clamp(0, start) : 0;
    final bytes = await filesystem.readBytesRange(
      path,
      readStart,
      size - readStart,
    );
    if (bytes == null || bytes.isEmpty) return const [];
    var first = 0;
    if (readStart > 0) {
      final before = await filesystem.readBytesRange(path, readStart - 1, 1);
      if (before == null || before.single != 0x0A) {
        final newline = bytes.indexOf(0x0A);
        if (newline < 0) return const [];
        first = newline + 1;
      }
    }
    return _splitLines(
      bytes.sublist(first),
      readStart + first,
      includeRemainder: true,
    );
  }

  Future<List<_TranscriptLine>> _readOlderLines(
    Filesystem filesystem,
    String path, {
    required int end,
    required int window,
  }) async {
    final start = end > window ? end - window : 0;
    final readStart = start > 0 ? (start - window).clamp(0, start) : 0;
    final bytes = await filesystem.readBytesRange(
      path,
      readStart,
      end - readStart,
    );
    if (bytes == null || bytes.isEmpty) return const [];
    var first = 0;
    if (readStart > 0) {
      final before = await filesystem.readBytesRange(path, readStart - 1, 1);
      if (before == null || before.single != 0x0A) {
        final newline = bytes.indexOf(0x0A);
        if (newline < 0) return const [];
        first = newline + 1;
      }
    }
    return _splitLines(
      bytes.sublist(first),
      readStart + first,
      includeRemainder: false,
    );
  }

  List<_TranscriptLine> _splitLines(
    List<int> bytes,
    int absoluteStart, {
    required bool includeRemainder,
  }) {
    final lines = <_TranscriptLine>[];
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != 0x0A) continue;
      final line = bytes.sublist(start, i);
      if (line.isNotEmpty) {
        lines.add(_TranscriptLine(offset: absoluteStart + start, bytes: line));
      }
      start = i + 1;
    }
    if (includeRemainder && start < bytes.length) {
      final line = bytes.sublist(start);
      if (line.isNotEmpty) {
        lines.add(_TranscriptLine(offset: absoluteStart + start, bytes: line));
      }
    }
    return lines;
  }

  Future<_TranscriptLine?> _readLineAt(
    Filesystem filesystem,
    String path,
    int offset,
    int size,
  ) async {
    final bytes = await filesystem.readBytesRange(path, offset, size - offset);
    if (bytes == null || bytes.isEmpty) return null;
    final end = bytes.indexOf(0x0A);
    final line = end < 0 ? bytes : bytes.sublist(0, end);
    return line.isEmpty ? null : _TranscriptLine(offset: offset, bytes: line);
  }

  static AiHistoryPage _emptyPage({
    required String sourceToken,
    required bool rebuilt,
  }) => AiHistoryPage(
    messages: const [],
    hasOlder: false,
    nextCursor: null,
    sourceToken: sourceToken,
    rebuilt: rebuilt,
  );

  Future<String?> _sourceToken(String path, FsStat stat) async {
    final size = stat.size;
    if (size == null) return null;
    final version = await _sourceVersion(path, stat);
    if (version == null || version.isEmpty) return null;
    return base64Url.encode(
      utf8.encode(jsonEncode({'path': path, 'size': size, 'version': version})),
    );
  }

  static Future<String?> _highPrecisionStatVersion(
    String _,
    FsStat stat,
  ) async {
    final mtime = stat.mtime;
    if (mtime == null) return null;
    final micros = mtime.toUtc().microsecondsSinceEpoch;
    // WSL `%Y` and SFTP attrs expose whole seconds. Such a value cannot
    // distinguish a same-size rewrite in the same second, so page reads must
    // fall back to the full adapter. A backend with a stronger native version
    // can provide it through [AiTranscriptSourceVersion].
    if (micros % Duration.microsecondsPerSecond == 0) return null;
    return 'mtime-us:$micros';
  }

  static ({String path, int size, String version})? _decodeSourceToken(
    String token,
  ) {
    try {
      final decoded = jsonDecode(utf8.decode(base64Url.decode(token)));
      if (decoded is! Map ||
          decoded['path'] is! String ||
          decoded['size'] is! int ||
          decoded['version'] is! String) {
        return null;
      }
      return (
        path: decoded['path'] as String,
        size: decoded['size'] as int,
        version: decoded['version'] as String,
      );
    } on Object {
      return null;
    }
  }

  static int _lineHash(List<int> line) {
    var hash = 0x811C9DC5;
    for (final byte in line) {
      hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  static bool _sameMessages(List<AiMessage> a, List<AiMessage> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.id != right.id ||
          left.role != right.role ||
          left.status != right.status ||
          left.createdAt != right.createdAt ||
          left.parts.length != right.parts.length)
        return false;
      for (var j = 0; j < left.parts.length; j++) {
        if (!_samePart(left.parts[j], right.parts[j])) return false;
      }
    }
    return true;
  }

  static bool _samePart(AiMessagePart a, AiMessagePart b) {
    if (a.runtimeType != b.runtimeType) return false;
    if (a is AiTextPart && b is AiTextPart) return a.text == b.text;
    if (a is AiReasoningPart && b is AiReasoningPart) return a.text == b.text;
    if (a is AiToolCallPart && b is AiToolCallPart) {
      return a.toolCallId == b.toolCallId &&
          a.toolName == b.toolName &&
          a.argsText == b.argsText &&
          a.result.toString() == b.result.toString() &&
          a.status == b.status &&
          a.isError == b.isError;
    }
    return false;
  }
}

final class _TranscriptLine {
  const _TranscriptLine({required this.offset, required this.bytes});

  final int offset;
  final List<int> bytes;
}

final class _ParsedLines {
  const _ParsedLines({
    required this.messages,
    required this.messageCounts,
    required this.fallbackUsed,
    required this.unresolvedDependency,
    required this.firstConsumedIndex,
    required this.firstConsumedRole,
    required this.consumedRoles,
  });

  final List<AiMessage> messages;
  final List<int> messageCounts;
  final bool fallbackUsed;
  final bool unresolvedDependency;
  final int? firstConsumedIndex;
  final AiRole? firstConsumedRole;
  final List<AiRole?> consumedRoles;
}
