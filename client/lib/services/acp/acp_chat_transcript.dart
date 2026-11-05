import 'dart:async';
import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import '../io/filesystem.dart';
import '../../utils/logging/logger.dart';
import 'acp_chat_transcript_replay.dart';
import 'acp_usage.dart';

/// Append-only transcript of one ACP chat session's folded messages.
///
/// v1 rewrote the whole snapshot on every commit: a long streaming turn grows
/// one assistant message to thousands of parts, so each tool-call update
/// re-encoded and `atomicWrite`-ed the entire file on the UI isolate. v2 keeps
/// [saveMessages] as a whole-snapshot API but diffs against the last committed
/// snapshot and appends only the changed records (one small line per changed
/// part). The encoding work is O(changed parts), not O(all parts), and the
/// disk write is an append instead of a multi-MB atomic rewrite.
///
/// Writes are coalesced: only the newest queued snapshot is applied, so a burst
/// of tool-call updates appends once instead of once per update. Each call
/// still resolves only after a write that includes its state (or newer) lands,
/// so [loadMessages] never observes an older snapshot.
///
/// A compact rewrite is done on the first write, when legacy v1 records are
/// detected, when messages are reordered/parts removed, or after
/// [compactAfterAppendedBytes] of appends — that bounds log growth while
/// keeping the per-commit path append-only.
///
/// Also appends `usage_update` samples to [usagePath] (JSONL) so the usage
/// collector can re-read them out-of-band; the transcript itself never carries
/// usage.
class AcpChatTranscriptWriter {
  AcpChatTranscriptWriter({
    required Filesystem fs,
    required this.path,
    this.usagePath,
    this.compactAfterAppendedBytes = defaultCompactAfterAppendedBytes,
  }) : _fs = fs;

  /// Compact after this many bytes have been appended since the last full
  /// rewrite. Base transcript size does not count, so a large session does not
  /// get rewritten on every commit.
  static const int defaultCompactAfterAppendedBytes = 4 * 1024 * 1024;

  final Filesystem _fs;
  final String path;

  /// JSONL sink for [AcpUsageRecord]s, or null when usage is not collected.
  final String? usagePath;
  final int compactAfterAppendedBytes;

  Future<void> _pending = Future<void>.value();

  /// Newest snapshot waiting to be written; supersedes earlier queued ones.
  List<AiMessage>? _queued;
  Completer<void>? _queuedDone;
  bool _draining = false;

  /// Last snapshot known to be on disk. `null` until [loadMessages] or the
  /// first [saveMessages] establishes a baseline.
  List<AiMessage>? _committed;

  /// True when the file still contains legacy v1 records that must be
  /// migrated to v2 before appending.
  bool _needsRewrite = false;
  int _appendedSinceCompact = 0;

  Future<List<AiMessage>> loadMessages() async {
    await _pending;
    final raw = await _fs.readString(path);
    final result = decodeAcpChatTranscriptResult(raw);
    if ((raw != null && raw.trim().isNotEmpty) && result.messages.isEmpty) {
      appLogger.w('[acp-transcript] ignored unreadable transcript path=$path');
    }
    // Decoded message instances are the same ones the runtime merges into its
    // state, so the next save can diff by identity at zero cost.
    _committed = result.messages;
    _needsRewrite = result.hasLegacyRecords;
    _appendedSinceCompact = 0;
    return result.messages;
  }

  Future<void> saveMessages(List<AiMessage> messages) {
    _queued = messages;
    final done = _queuedDone ??= Completer<void>();
    if (!_draining) {
      _draining = true;
      _pending = _drain().catchError((Object _) {});
    }
    return done.future;
  }

  Future<void> _drain() async {
    try {
      while (_queued != null) {
        final snapshot = _queued!;
        final done = _queuedDone!;
        _queued = null;
        _queuedDone = null;
        try {
          await _write(snapshot);
        } on Object catch (error, stackTrace) {
          done.completeError(error, stackTrace);
          final queuedDone = _queuedDone;
          _queued = null;
          _queuedDone = null;
          queuedDone?.completeError(error, stackTrace);
          rethrow;
        }
        done.complete();
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _write(List<AiMessage> snapshot) async {
    final committed = _committed;
    // No baseline yet: do one compact write instead of reading the file back.
    // This also keeps save-before-load callers (tests, cold seeding) correct.
    final delta = committed == null
        ? null
        : buildAcpChatTranscriptDelta(previous: committed, next: snapshot);
    if (committed != null && !_needsRewrite && delta != null && delta.isEmpty) {
      // Repeated _persist calls at a turn boundary carry no new state.
      _committed = snapshot;
      return;
    }
    final compact =
        committed == null ||
        _needsRewrite ||
        delta == null ||
        _appendedSinceCompact >= compactAfterAppendedBytes;

    if (compact) {
      await _fs.atomicWrite(path, encodeAcpChatTranscript(snapshot));
      _appendedSinceCompact = 0;
      _needsRewrite = false;
    } else if (delta.isNotEmpty) {
      final buffer = StringBuffer();
      for (final record in delta) {
        buffer.writeln(jsonEncode(record));
      }
      final text = buffer.toString();
      try {
        await _fs.appendString(path, text);
      } on Object {
        // A partial append may already contain complete `text` records. The
        // next save must compact from the snapshot instead of re-emitting the
        // same suffix, otherwise replay would duplicate streamed text.
        _needsRewrite = true;
        rethrow;
      }
      _appendedSinceCompact += utf8.encode(text).length;
    }
    // An unchanged snapshot writes nothing at all.
    _committed = snapshot;
  }

  /// Appends one `usage_update` sample as a JSONL record.
  ///
  /// Serialized through the same queue as [saveMessages] so a chat snapshot
  /// and a usage record never interleave writes. No-op when [usagePath] is
  /// unset.
  Future<void> appendUsage({
    required String sessionId,
    required int? used,
    required int? size,
    Object? cost,
    String? model,
  }) {
    final target = usagePath;
    if (target == null || target.trim().isEmpty) return Future<void>.value();
    final record = AcpUsageRecord.fromUpdate(
      sessionId: sessionId,
      used: used,
      size: size,
      cost: cost,
      model: model,
    );
    final next = _pending.then((_) async {
      await _fs.ensureDir(_fs.pathContext.dirname(target));
      await _fs.appendString(target, '${jsonEncode(record.toJson())}\n');
    });
    _pending = next.catchError((Object _) {});
    return next;
  }
}
