import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import 'attention_batch.dart';
import 'attention_cursor.dart';
import 'attention_event.dart';

/// Append-only attention log owned by the process that owns the seat runtime.
///
/// `seq` is assigned here, in append order. With [fs] + [path] every event is
/// persisted before it is emitted. A failed file write is logged and the event
/// is still emitted: losing one notification is worse than losing durability
/// for that one event. The log then stays dirty until a compaction succeeds, so
/// the next append rewrites the file with the events memory still holds.
final class AttentionLog {
  AttentionLog({
    required this.authorityId,
    required this.epoch,
    Filesystem? fs,
    String? path,
    DateTime Function()? clock,
    this.retention = const Duration(days: 7),
    this.maxEvents = 1000,
    String Function()? eventId,
  }) : _fs = fs,
       _path = path,
       _clock = clock ?? DateTime.now,
       _eventId = eventId ?? (() => const Uuid().v7());

  static const tag = 'attention';

  final String authorityId;
  final int epoch;
  final Duration retention;
  final int maxEvents;
  final Filesystem? _fs;
  final String? _path;
  final DateTime Function() _clock;
  final String Function() _eventId;

  final List<AttentionEvent> _events = [];
  final StreamController<AttentionEvent> _appended =
      StreamController<AttentionEvent>.broadcast();
  Future<void> _queue = Future<void>.value();
  int _nextSeq = 1;
  bool _closed = false;

  /// Set when a write failed, so the next successful append/compaction
  /// reconciles the file with the events memory holds.
  bool _dirty = false;

  Stream<AttentionEvent> get appended => _appended.stream;

  List<AttentionEvent> get events => List.unmodifiable(_events);

  int get earliestSeq => _events.isEmpty ? _nextSeq : _events.first.seq;

  int get latestSeq => _nextSeq - 1;

  /// Opens a file-backed log.
  ///
  /// Throws when an existing on-disk log cannot be read or its directory cannot
  /// be prepared, because assigning new sequence numbers without the loaded
  /// contents would violate `(authorityId, epoch)` monotonicity. Corrupt
  /// individual lines are skipped.
  static Future<AttentionLog> open({
    required String authorityId,
    required int epoch,
    required Filesystem fs,
    required String path,
    DateTime Function()? clock,
    Duration retention = const Duration(days: 7),
    int maxEvents = 1000,
    String Function()? eventId,
  }) async {
    final log = AttentionLog(
      authorityId: authorityId,
      epoch: epoch,
      fs: fs,
      path: path,
      clock: clock,
      retention: retention,
      maxEvents: maxEvents,
      eventId: eventId,
    );
    await log._load();
    return log;
  }

  Future<void> _load() async {
    final fs = _fs;
    final path = _path;
    if (fs == null || path == null) return;
    await fs.ensureDir(fs.pathContext.dirname(path));
    final raw = await fs.readString(path);
    if (raw == null || raw.trim().isEmpty) return;
    var maxSeq = 0;
    for (final line in const LineSplitter().convert(raw)) {
      if (line.trim().isEmpty) continue;
      try {
        final event = AttentionEvent.fromJson(jsonDecode(line));
        if (event == null ||
            event.authorityId != authorityId ||
            event.epoch != epoch) {
          continue;
        }
        _events.add(event);
        if (event.seq > maxSeq) maxSeq = event.seq;
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[$tag] skipping corrupt log line path=$path',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    _events.sort((a, b) => a.seq.compareTo(b.seq));
    _nextSeq = maxSeq + 1;
    _pruneMemory();
  }

  Future<AttentionEvent> append({
    required String sessionId,
    required String memberId,
    required AttentionKind kind,
    String? turnId,
    String workspaceId = '',
    String title = '',
    String message = '',
    Map<String, Object?> payload = const {},
    DateTime? occurredAt,
  }) {
    if (_closed) {
      return Future<AttentionEvent>.error(
        StateError('attention log is closed'),
      );
    }
    final completer = Completer<AttentionEvent>();
    _queue = _queue.catchError((Object _) {}).then((_) async {
      try {
        final now = (occurredAt ?? _clock()).toUtc();
        final event = AttentionEvent(
          eventId: _eventId(),
          authorityId: authorityId,
          epoch: epoch,
          seq: _nextSeq++,
          sessionId: sessionId,
          memberId: memberId,
          turnId: turnId,
          workspaceId: workspaceId,
          kind: kind,
          occurredAt: now,
          expiresAt: now.add(retention),
          title: title,
          message: message,
          payload: payload,
        );
        final persisted = await _persist(event);
        _events.add(event);
        final pruned = _pruneMemory();
        if (!persisted || _dirty || pruned) {
          _dirty = !await _compact();
        }
        if (!_appended.isClosed) _appended.add(event);
        completer.complete(event);
      } on Object catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });
    return completer.future;
  }

  AttentionBatch slice({AttentionCursor? cursor, int limit = 200}) {
    final earliest = earliestSeq;
    final latest = latestSeq;
    var baseSeq = latest;
    var start = 0;
    var gap = false;
    final current = cursor;
    if (current != null &&
        current.authorityId == authorityId &&
        current.epoch == epoch) {
      baseSeq = current.seq;
      if (current.seq < earliest - 1) {
        gap = true;
        start = 0;
      } else {
        start = _events.indexWhere((event) => event.seq > current.seq);
        if (start < 0) start = _events.length;
      }
    }
    final events = _events.skip(start).take(limit).toList(growable: false);
    return AttentionBatch(
      authorityId: authorityId,
      epoch: epoch,
      fromSeq: events.isEmpty ? baseSeq + 1 : events.first.seq,
      toSeq: events.isEmpty ? (gap ? earliest - 1 : baseSeq) : events.last.seq,
      events: events,
      gap: gap,
    );
  }

  /// Appends [event] to the file. Returns `false` when the write failed; the
  /// caller keeps the event in memory and reconciles on the next compaction.
  Future<bool> _persist(AttentionEvent event) async {
    final fs = _fs;
    final path = _path;
    if (fs == null || path == null) return true;
    try {
      await fs.appendString(path, '${jsonEncode(event.toJson())}\n');
      return true;
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[$tag] append failed path=$path',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  bool _pruneMemory() {
    final now = _clock().toUtc();
    final before = _events.length;
    _events.removeWhere((event) => !event.expiresAt.isAfter(now));
    if (_events.length > maxEvents) {
      _events.removeRange(0, _events.length - maxEvents);
    }
    return _events.length != before;
  }

  /// Rewrites the file from memory. Returns `false` when the write failed.
  Future<bool> _compact() async {
    final fs = _fs;
    final path = _path;
    if (fs == null || path == null) return true;
    try {
      final content = _events.isEmpty
          ? ''
          : '${_events.map((event) => jsonEncode(event.toJson())).join('\n')}\n';
      await fs.atomicWrite(path, content);
      return true;
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[$tag] compact failed path=$path',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _queue;
    if (!_appended.isClosed) await _appended.close();
  }
}
