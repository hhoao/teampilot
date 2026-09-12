import 'dart:async';
import 'dart:convert';

import 'acp_session.dart';
import '../io/filesystem.dart';

/// Append-only app-side record of one ACP chat session's messages.
///
/// Per the design spec, the app-side message table is the single source for
/// ACP sessions — the CLI's own on-disk transcript is never read. Each event
/// is one JSONL line; `seq` is a monotonically increasing ordinal owned by
/// this writer.
class AcpChatTranscriptWriter {
  AcpChatTranscriptWriter({required Filesystem fs, required this.path})
    : _fs = fs;

  final Filesystem _fs;
  final String path;

  int _seq = 0;
  bool _hydrated = false;

  /// Serializes record writes: stream events can arrive faster than the
  /// (async) fs append completes, and the fs append is read-modify-write —
  /// an unserialized pair of records would drop one line.
  Future<void> _pending = Future<void>.value();

  /// Number of records written so far (lifetime of this writer).
  int get writtenCount => _seq;

  /// Runs [write] strictly after the previous record completes.
  Future<void> _enqueue(Future<void> Function() write) {
    final next = _pending.then((_) => write());
    // Keep the chain alive even when a write fails (e.g. torn tail).
    _pending = next.catchError((Object _) {});
    return next;
  }

  /// Scans the existing file (once) to continue the seq ordinal.
  Future<void> _ensureHydrated() async {
    if (_hydrated) return;
    _hydrated = true;
    final existing = await _fs.readString(path);
    if (existing == null || existing.isEmpty) return;
    var maxSeq = -1;
    for (final line in existing.split('\n')) {
      if (line.trim().isEmpty) continue;
      try {
        final entry = jsonDecode(line);
        if (entry is Map<String, Object?>) {
          final seq = entry['seq'];
          if (seq is int && seq > maxSeq) maxSeq = seq;
        }
      } on FormatException {
        // Torn tail line from a crash mid-append: skip.
      }
    }
    _seq = maxSeq + 1;
  }

  Future<void> _append(Map<String, Object?> entry) => _enqueue(() async {
    await _ensureHydrated();
    entry['seq'] = _seq++;
    await _fs.appendBytes(path, utf8.encode('${jsonEncode(entry)}\n'));
  });

  /// Records the user's prompt text for a turn.
  Future<void> recordUserPrompt(String text) => _append({
    'type': 'user',
    'text': text,
    'at': DateTime.now().toUtc().toIso8601String(),
  });

  /// Records one streamed message chunk.
  Future<void> recordChunk(AcpMessageChunk chunk) => _append({
    'type': 'chunk',
    'role': chunk.role.name,
    'text': chunk.content,
    'thought': chunk.isThought,
    'at': DateTime.now().toUtc().toIso8601String(),
  });

  /// Records a tool-call update (title/status transitions).
  Future<void> recordToolCall(AcpToolCallUpdate update) => _append({
    'type': 'tool_call',
    'toolCallId': update.toolCallId,
    if (update.title != null) 'title': update.title,
    if (update.status != null) 'status': update.status!.name,
    'at': DateTime.now().toUtc().toIso8601String(),
  });

  /// Records the terminal stop event of a turn.
  Future<void> recordStop(AcpStop stop) => _append({
    'type': 'stop',
    'kind': stop.kind.name,
    if (stop.message != null) 'message': stop.message,
    'at': DateTime.now().toUtc().toIso8601String(),
  });

  /// Records a session-lifecycle system message (launch failure, crash).
  Future<void> recordSystem(String kind, String message) => _append({
    'type': 'system',
    'kind': kind,
    'message': message,
    'at': DateTime.now().toUtc().toIso8601String(),
  });
}
