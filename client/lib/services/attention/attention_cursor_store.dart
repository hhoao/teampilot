import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import 'attention_cursor.dart';
import 'attention_event.dart';

/// Device-local cursor + seen-event store.
///
/// Cursors are keyed by home id (`RuntimeTarget.id`) so switching between a
/// local home and an SSH home never reuses the wrong authority position.
///
/// Loading is retryable: when the initial read fails [load] returns `false` and
/// writes are rejected rather than overwriting a file this process could not
/// read. Mutations are serialized and transactional: in-memory state is reverted
/// when persistence fails, so [cursorFor] only advertises durable state.
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
  final List<String> _evicted = [];
  final Set<String> _evictedSet = {};

  /// Homes cleared before the first successful load; a lazy load must not
  /// resurrect them from disk.
  final Set<String> _clearedHomes = {};

  Future<bool> _queue = Future<bool>.value(true);

  /// Cached in-flight/settled load so concurrent callers await the same read.
  ///
  /// Cleared again when the read fails, which lets a later [load] retry.
  Future<bool>? _loadFuture;

  /// True only once a read has completed successfully (or no fs/path is set).
  bool _loaded = false;

  /// Returns `true` when the state is usable, including memory-only/no-path and
  /// a self-healed corrupt file. Returns `false` on read failure.
  Future<bool> load() {
    final pending = _loadFuture;
    if (pending != null) return pending;
    final future = _doLoad().then((ok) {
      if (!ok) _loadFuture = null;
      return ok;
    });
    return _loadFuture = future;
  }

  Future<bool> _doLoad() async {
    final fs = _fs;
    final path = _path;
    if (fs == null || path == null) {
      _loaded = true;
      return true;
    }
    try {
      final raw = await fs.readString(path);
      if (raw != null && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            _applyCursors(decoded['cursors']);
            _applySeenEventIds(decoded['seenEventIds']);
            _applyEvictedEventIds(decoded['evictedEventIds']);
            _trimSeen();
            _trimEvicted();
          }
        } on FormatException catch (error, stackTrace) {
          // Corrupt file: fall back to empty state and let the next write
          // replace it instead of blocking persistence forever.
          appLogger.w(
            '[$tag] cursor file corrupt; resetting path=$path',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      _loaded = true;
      return true;
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[$tag] cursor load failed path=$path',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  void _applyCursors(Object? json) {
    if (json is! Map) return;
    for (final entry in json.entries) {
      final homeId = entry.key.toString();
      if (_clearedHomes.contains(homeId)) continue;
      final cursor = AttentionCursor.fromJson(entry.value);
      if (cursor == null) continue;
      _cursors.putIfAbsent(homeId, () => cursor);
    }
  }

  void _applySeenEventIds(Object? json) {
    if (json is! List) return;
    _seen.insertAll(0, [
      for (final id in json)
        if (id is String && id.isNotEmpty && _seenSet.add(id)) id,
    ]);
  }

  void _applyEvictedEventIds(Object? json) {
    if (json is! List) return;
    _evicted.insertAll(0, [
      for (final id in json)
        if (id is String && id.isNotEmpty && _evictedSet.add(id)) id,
    ]);
  }

  void _trimSeen() {
    if (_seen.length <= _maxSeenEventIds) return;
    final drop = _seen.length - _maxSeenEventIds;
    for (final id in _seen.take(drop)) {
      _seenSet.remove(id);
      _rememberEvicted(id);
    }
    _seen.removeRange(0, drop);
    _trimEvicted();
  }

  void _rememberEvicted(String id) {
    if (id.isEmpty || !_evictedSet.add(id)) return;
    _evicted.add(id);
  }

  void _trimEvicted() {
    if (_evicted.length <= _maxSeenEventIds) return;
    final drop = _evicted.length - _maxSeenEventIds;
    for (final id in _evicted.take(drop)) {
      _evictedSet.remove(id);
    }
    _evicted.removeRange(0, drop);
  }

  AttentionCursor? cursorFor(String homeId) => _cursors[homeId];

  bool hasSeen(String eventId) => _seenSet.contains(eventId);

  bool wasRecentlyEvicted(String eventId) => _evictedSet.contains(eventId);

  /// True when [event] is a duplicate covered by durable state: in the seen
  /// window, or recently evicted and at/below the matching authority/epoch
  /// cursor. Genuinely unseen in-window out-of-order events are not suppressed.
  bool isSuppressed(AttentionEvent event, {AttentionCursor? cursor}) {
    if (_seenSet.contains(event.eventId)) return true;
    if (!_evictedSet.contains(event.eventId)) return false;
    final current = cursor;
    if (current == null) return false;
    return event.authorityId == current.authorityId &&
        event.epoch == current.epoch &&
        event.seq <= current.seq;
  }

  /// Persists [cursor] and [eventIds] for [homeId].
  ///
  /// Returns `true` only when the state is durably written or memory-only.
  /// Returns `false` when persistence failed or state is unavailable; in that
  /// case the in-memory mutation is reverted so [cursorFor] remains durable.
  Future<bool> remember(
    String homeId,
    AttentionCursor cursor,
    Iterable<String> eventIds,
  ) {
    return _mutate(() {
      final previousCursor = _cursors[homeId];
      final wasCleared = _clearedHomes.remove(homeId);
      final previousSeen = List<String>.of(_seen);
      final previousSeenSet = Set<String>.of(_seenSet);
      final previousEvicted = List<String>.of(_evicted);
      final previousEvictedSet = Set<String>.of(_evictedSet);
      _cursors[homeId] = cursor;
      for (final id in eventIds) {
        if (id.isEmpty || !_seenSet.add(id)) continue;
        _seen.add(id);
      }
      _trimSeen();
      return () {
        if (previousCursor == null) {
          _cursors.remove(homeId);
        } else {
          _cursors[homeId] = previousCursor;
        }
        if (wasCleared) _clearedHomes.add(homeId);
        _seen
          ..clear()
          ..addAll(previousSeen);
        _seenSet
          ..clear()
          ..addAll(previousSeenSet);
        _evicted
          ..clear()
          ..addAll(previousEvicted);
        _evictedSet
          ..clear()
          ..addAll(previousEvictedSet);
      };
    });
  }

  /// Removes [homeId]'s cursor.
  ///
  /// Returns `true` only when the removal is durably written or memory-only.
  Future<bool> clearCursor(String homeId) {
    return _mutate(() {
      final previousCursor = _cursors[homeId];
      final hadCursor = _cursors.containsKey(homeId);
      final wasCleared = _clearedHomes.contains(homeId);
      _cursors.remove(homeId);
      _clearedHomes.add(homeId);
      return () {
        if (hadCursor && previousCursor != null) {
          _cursors[homeId] = previousCursor;
        }
        if (!wasCleared) _clearedHomes.remove(homeId);
      };
    });
  }

  Future<bool> _mutate(void Function() Function() apply) {
    _queue = _queue.catchError((Object _) => true).then((_) async {
      if (!_loaded) {
        final ok = await load();
        if (!ok) {
          final fs = _fs;
          final path = _path;
          if (fs != null && path != null) {
            appLogger.w(
              '[$tag] mutation rejected: cursor state unavailable path=$path',
            );
            return false;
          }
        }
      }
      final revert = apply();
      final persisted = await _writeSnapshot();
      if (!persisted) {
        revert();
        return false;
      }
      return true;
    });
    return _queue;
  }

  Future<bool> _writeSnapshot() async {
    final fs = _fs;
    final path = _path;
    if (fs == null || path == null) return true;
    if (!_loaded) {
      appLogger.w('[$tag] skip save: cursor state unavailable path=$path');
      return false;
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
          'evictedEventIds': _evicted,
        }),
      );
      return true;
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[$tag] cursor save failed path=$path',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}
