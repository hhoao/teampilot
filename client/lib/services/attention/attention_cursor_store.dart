import 'dart:async';
import 'dart:convert';

import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import 'attention_cursor.dart';

/// Device-local cursor + seen-event store.
///
/// Cursors are keyed by home id (`RuntimeTarget.id`) so switching between a
/// local home and an SSH home never reuses the wrong authority position.
///
/// Loading is retryable: when the initial read fails the store stays
/// unloaded, and writes are skipped rather than overwriting a file this
/// process could not read.
final class AttentionCursorStore {
  AttentionCursorStore({
    Filesystem? fs,
    String? path,
    int maxSeenEventIds = 512,
  }) : assert(maxSeenEventIds > 0, 'maxSeenEventIds must be positive'),
       _fs = fs,
       _path = path,
       _maxSeenEventIds = maxSeenEventIds;

  static const tag = 'attention';

  final Filesystem? _fs;
  final String? _path;
  final int _maxSeenEventIds;

  final Map<String, AttentionCursor> _cursors = {};
  final List<String> _seen = [];
  final Set<String> _seenSet = {};

  /// Homes cleared before the first successful load; a lazy load must not
  /// resurrect them from disk.
  final Set<String> _clearedHomes = {};

  Future<void> _queue = Future<void>.value();

  /// Cached in-flight/settled load so concurrent callers await the same read.
  ///
  /// Cleared again when the read throws, which lets a later [load] retry.
  Future<void>? _loadFuture;

  /// True only once a read has completed successfully (or no fs/path is set).
  bool _loaded = false;

  Future<void> load() {
    final pending = _loadFuture;
    if (pending != null) return pending;
    return _loadFuture = _doLoad().whenComplete(() {
      // A failed read must stay retryable; only keep the cache on success.
      if (!_loaded) _loadFuture = null;
    });
  }

  Future<void> _doLoad() async {
    final fs = _fs;
    final path = _path;
    if (fs == null || path == null) {
      _loaded = true;
      return;
    }
    try {
      final raw = await fs.readString(path);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _applyCursors(decoded['cursors']);
          _applySeenEventIds(decoded['seenEventIds']);
          _trimSeen();
        }
      }
      _loaded = true;
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[$tag] cursor load failed path=$path',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _applyCursors(Object? json) {
    if (json is! Map) return;
    for (final entry in json.entries) {
      final homeId = entry.key.toString();
      if (_clearedHomes.contains(homeId)) continue;
      final cursor = AttentionCursor.fromJson(entry.value);
      if (cursor == null) continue;
      // Keep an in-memory cursor: a lazy load can run after `remember` mutated
      // it, and that mutation is newer than the file.
      _cursors.putIfAbsent(homeId, () => cursor);
    }
  }

  void _applySeenEventIds(Object? json) {
    if (json is! List) return;
    // Disk ids predate anything `remember` added while the store was unloaded,
    // so splice them in front to keep `_seen` ordered oldest -> newest.
    _seen.insertAll(0, [
      for (final id in json)
        if (id is String && id.isNotEmpty && _seenSet.add(id)) id,
    ]);
  }

  void _trimSeen() {
    if (_seen.length <= _maxSeenEventIds) return;
    final drop = _seen.length - _maxSeenEventIds;
    for (final id in _seen.take(drop)) {
      _seenSet.remove(id);
    }
    _seen.removeRange(0, drop);
  }

  AttentionCursor? cursorFor(String homeId) => _cursors[homeId];

  bool hasSeen(String eventId) => _seenSet.contains(eventId);

  Future<void> remember(
    String homeId,
    AttentionCursor cursor,
    Iterable<String> eventIds,
  ) {
    _clearedHomes.remove(homeId);
    _cursors[homeId] = cursor;
    for (final id in eventIds) {
      if (id.isEmpty || !_seenSet.add(id)) continue;
      _seen.add(id);
    }
    _trimSeen();
    return _persist();
  }

  Future<void> clearCursor(String homeId) {
    _cursors.remove(homeId);
    _clearedHomes.add(homeId);
    return _persist();
  }

  Future<void> _persist() {
    _queue = _queue.catchError((Object _) {}).then((_) async {
      final fs = _fs;
      final path = _path;
      if (fs == null || path == null) return;
      if (!_loaded) {
        await load();
        if (!_loaded) {
          appLogger.w('[$tag] skip save: cursor state unavailable path=$path');
          return;
        }
      }
      try {
        await fs.ensureDir(fs.pathContext.dirname(path));
        await fs.atomicWrite(
          path,
          const JsonEncoder.withIndent('  ').convert({
            'version': 1,
            'cursors': {
              for (final entry in _cursors.entries)
                entry.key: entry.value.toJson(),
            },
            'seenEventIds': _seen,
          }),
        );
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[$tag] cursor save failed path=$path',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
    return _queue;
  }
}
