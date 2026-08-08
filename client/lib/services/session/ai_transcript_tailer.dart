import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import '../cli/registry/capabilities/history/claude_compatible_jsonl.dart';
import 'session_history_context.dart';

class TailRefreshResult {
  const TailRefreshResult({
    required this.messages,
    required this.pathKey,
    required this.changed,
    this.fullReseek = false,
  });

  final List<AiMessage> messages;
  final String? pathKey;
  final bool changed;
  final bool fullReseek;
}

/// Incremental reader for an append-only JSONL transcript.
///
/// Holds per-seat cursor state and re-reads only the appended tail, so a live
/// refresh is O(appended bytes) instead of O(file). A full re-seek happens on
/// force, a path change, a `pathKey` change (first-line fingerprint — catches
/// compaction and in-place rewrites), or a shrink. The fingerprint is
/// deliberately first-line only: `mtime` and `size` change on every append, so
/// including them would force a full re-seek on each tail and defeat the delta
/// path; a rewrite is instead detected by the shrink branch or by the first
/// line changing.
final class AiTranscriptTailer {
  AiTranscriptTailer({this.maxFirstLineBytes = 4096});

  final int maxFirstLineBytes;

  final Map<String, _TailState> _states = {};

  /// Evicts every seat cursor (loader `clearCache`).
  void clear() => _states.clear();

  void remove(String seatKey) => _states.remove(seatKey);

  void removeWhere(bool Function(String seatKey) test) =>
      _states.removeWhere((key, _) => test(key));

  Future<TailRefreshResult> refresh({
    required SessionHistoryContext ctx,
    required String seatKey,
    required String? transcriptPath,
    bool force = false,
  }) async {
    final state = _states.putIfAbsent(seatKey, _TailState.new);
    final path = _trimmed(transcriptPath);

    final stat = path == null ? null : await ctx.fs.stat(path);
    if (path == null || stat == null || !stat.exists || stat.isDirectory) {
      _states.remove(seatKey);
      return const TailRefreshResult(
        messages: [],
        pathKey: null,
        changed: false,
      );
    }
    final size = stat.size ?? -1;
    final pathKey = await _pathKey(ctx, path, size);

    final fullReseek =
        force ||
        state.path != path ||
        state.pathKey != pathKey ||
        size < state.byteOffset;
    if (fullReseek) {
      // Consume complete lines only and defer any trailing partial line (and
      // any trailing partial multi-byte char) to the delta path: land byteOffset
      // on the byte after the last '\n' so the next delta starts at a valid
      // boundary instead of mid-code-point.
      final content = await ctx.fs.readBytes(path);
      state.raw.clear();
      if (content != null) {
        final lastNl = content.lastIndexOf(0x0A);
        final consumed =
            lastNl < 0 ? const <int>[] : content.sublist(0, lastNl + 1);
        state.byteOffset = lastNl < 0 ? 0 : lastNl + 1;
        final text = utf8.decode(consumed, allowMalformed: true);
        for (final line in const LineSplitter().convert(text)) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          final event = tryDecodeJsonlLine(trimmed);
          if (event == null) continue;
          appendClaudeJsonlEvent(
            state.raw,
            event,
            fallbackId: () => 'full-$seatKey',
          );
        }
      }
      state
        ..path = path
        ..pathKey = pathKey
        ..finalized = finalizeAiMessagesForHistory(state.raw);
      return TailRefreshResult(
        messages: state.finalized,
        pathKey: pathKey,
        changed: true,
        fullReseek: true,
      );
    }

    if (size == state.byteOffset) {
      return TailRefreshResult(
        messages: state.finalized,
        pathKey: pathKey,
        changed: false,
      );
    }

    // Delta: consume the appended tail up to the last '\n'.
    final tail = await ctx.fs.readBytesRange(
      path,
      state.byteOffset,
      size - state.byteOffset,
    );
    if (tail == null || tail.isEmpty) {
      state.byteOffset = size;
      return TailRefreshResult(
        messages: state.finalized,
        pathKey: pathKey,
        changed: false,
      );
    }
    final lastNl = tail.lastIndexOf(0x0A);
    if (lastNl < 0) {
      // Mid-write partial line; defer until a '\n' lands.
      return TailRefreshResult(
        messages: state.finalized,
        pathKey: pathKey,
        changed: false,
      );
    }
    final consumed = tail.sublist(0, lastNl + 1);
    state.byteOffset += consumed.length;
    // Ends at '\n' (0x0A), so this is always a valid UTF-8 boundary; tolerate
    // stray malformed bytes (defense-in-depth, mirrors readString/the enricher).
    final content = utf8.decode(consumed, allowMalformed: true);
    for (final line in const LineSplitter().convert(content)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final event = tryDecodeJsonlLine(trimmed);
      if (event == null) continue;
      appendClaudeJsonlEvent(state.raw, event, fallbackId: () => 'delta-$seatKey');
    }
    state.finalized = finalizeAiMessagesForHistory(state.raw);
    return TailRefreshResult(
      messages: state.finalized,
      pathKey: pathKey,
      changed: true,
    );
  }

  Future<String?> _pathKey(
    SessionHistoryContext ctx,
    String path,
    int size,
  ) async {
    if (size <= 0) return '$size:0';
    final head = await ctx.fs.readBytesRange(path, 0, maxFirstLineBytes);
    return _firstLineFromBytes(head).hashCode.toString();
  }

  static String _firstLineFromBytes(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) return '';
    final end = bytes.indexOf(0x0A);
    final len = end < 0 ? bytes.length : end;
    return utf8.decode(bytes.sublist(0, len), allowMalformed: true);
  }

  static String? _trimmed(String? value) {
    final t = value?.trim() ?? '';
    return t.isEmpty ? null : t;
  }
}

class _TailState {
  String? path;
  String? pathKey;
  int byteOffset = 0;
  final List<AiMessage> raw = [];
  List<AiMessage> finalized = const [];
}
