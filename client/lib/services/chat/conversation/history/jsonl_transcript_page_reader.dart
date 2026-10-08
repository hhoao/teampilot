import 'dart:convert';

import '../../../cli/registry/capabilities/ai_history_capability.dart';
import '../../../io/filesystem.dart';
import 'ai_transcript_tail_reader.dart';
import 'jsonl_page_worker.dart';
import 'jsonl_transcript_page_parser.dart';
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
  }) : _fallbackPrefix = fallbackPrefix,
       _sourcePath = sourcePath,
       _sourceVersion = sourceVersion ?? _highPrecisionStatVersion;

  /// Test override. Production reads go through [SessionHistoryContext.fs].
  final Filesystem? fs;

  Filesystem _boundFs(SessionHistoryContext ctx) => fs ?? ctx.fs;
  final String _fallbackPrefix;
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
      final AiHistoryPage? page;
      try {
        page = await _buildPage(
          lines,
          limit: limit,
          sourceToken: sourceToken,
          rebuilt: true,
        );
      } on Object {
        return null;
      }
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
    if (source == null || source.path != path || source.size != size) {
      return null;
    }
    final currentToken = await _sourceToken(path, stat);
    if (currentToken == null || currentToken != cursor.sourceToken) return null;
    if (cursor.offset <= 0 || cursor.offset > size) return null;
    final anchor = await _readLineAt(filesystem, path, cursor.offset, size);
    if (anchor == null ||
        JsonlTranscriptPageParser.lineHash(anchor.bytes) != cursor.lineHash) {
      return null;
    }

    for (final window in _windowsFor(cursor.offset)) {
      final lines = await _readOlderLines(
        filesystem,
        path,
        end: cursor.offset,
        window: window,
      );
      final AiHistoryPage? page;
      try {
        page = await _buildPage(
          lines,
          limit: limit,
          sourceToken: cursor.sourceToken,
          rebuilt: false,
        );
      } on Object {
        return null;
      }
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
    List<JsonlTranscriptLine> lines, {
    required int limit,
    required String sourceToken,
    required bool rebuilt,
  }) async {
    if (lines.isEmpty) {
      return _emptyPage(sourceToken: sourceToken, rebuilt: rebuilt);
    }
    return JsonlPageWorker.instance.parse(
      adapterId: _fallbackPrefix,
      lines: lines,
      limit: limit,
      sourceToken: sourceToken,
      rebuilt: rebuilt,
    );
  }

  Future<List<JsonlTranscriptLine>> _readLatestLines(
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

  Future<List<JsonlTranscriptLine>> _readOlderLines(
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

  List<JsonlTranscriptLine> _splitLines(
    List<int> bytes,
    int absoluteStart, {
    required bool includeRemainder,
  }) {
    final lines = <JsonlTranscriptLine>[];
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != 0x0A) continue;
      final line = bytes.sublist(start, i);
      if (line.isNotEmpty) {
        lines.add(
          JsonlTranscriptLine(offset: absoluteStart + start, bytes: line),
        );
      }
      start = i + 1;
    }
    if (includeRemainder && start < bytes.length) {
      final line = bytes.sublist(start);
      if (line.isNotEmpty) {
        lines.add(
          JsonlTranscriptLine(offset: absoluteStart + start, bytes: line),
        );
      }
    }
    return lines;
  }

  Future<JsonlTranscriptLine?> _readLineAt(
    Filesystem filesystem,
    String path,
    int offset,
    int size,
  ) async {
    final bytes = await filesystem.readBytesRange(path, offset, size - offset);
    if (bytes == null || bytes.isEmpty) return null;
    final end = bytes.indexOf(0x0A);
    final line = end < 0 ? bytes : bytes.sublist(0, end);
    return line.isEmpty
        ? null
        : JsonlTranscriptLine(offset: offset, bytes: line);
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
}
