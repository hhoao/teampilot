import 'dart:async';
import 'dart:convert';

import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import 'attention_cursor.dart';

/// Device-local cursor + seen-event store.
///
/// Cursors are keyed by home id (`RuntimeTarget.id`) so switching between a
/// local home and an SSH home never reuses the wrong authority position.
final class AttentionCursorStore {
  AttentionCursorStore({
    Filesystem? fs,
    String? path,
    int maxSeenEventIds = 512,
  }) : _fs = fs,
       _path = path,
       _maxSeenEventIds = maxSeenEventIds;

  static const tag = 'attention';

  final Filesystem? _fs;
  final String? _path;
  final int _maxSeenEventIds;

  final Map<String, AttentionCursor> _cursors = {};
  final List<String> _seen = [];
  final Set<String> _seenSet = {};
  Future<void> _queue = Future<void>.value();
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final fs = _fs;
    final path = _path;
    if (fs == null || path == null) return;
    try {
      final raw = await fs.readString(path);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final cursors = decoded['cursors'];
      if (cursors is Map) {
        for (final entry in cursors.entries) {
          final cursor = AttentionCursor.fromJson(entry.value);
          if (cursor != null) {
            _cursors[entry.key.toString()] = cursor;
          }
        }
      }
      final seen = decoded['seenEventIds'];
      if (seen is List) {
        for (final id in seen) {
          if (id is String && id.isNotEmpty && _seenSet.add(id)) {
            _seen.add(id);
          }
        }
      }
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[$tag] cursor load failed path=$path',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  AttentionCursor? cursorFor(String homeId) => _cursors[homeId];

  bool hasSeen(String eventId) => _seenSet.contains(eventId);

  Future<void> remember(
    String homeId,
    AttentionCursor cursor,
    Iterable<String> eventIds,
  ) {
    _cursors[homeId] = cursor;
    for (final id in eventIds) {
      if (id.isEmpty || !_seenSet.add(id)) continue;
      _seen.add(id);
    }
    if (_seen.length > _maxSeenEventIds) {
      final drop = _seen.length - _maxSeenEventIds;
      for (final id in _seen.take(drop)) {
        _seenSet.remove(id);
      }
      _seen.removeRange(0, drop);
    }
    return _persist();
  }

  Future<void> clearCursor(String homeId) {
    _cursors.remove(homeId);
    return _persist();
  }

  Future<void> _persist() {
    _queue = _queue.catchError((Object _) {}).then((_) async {
      final fs = _fs;
      final path = _path;
      if (fs == null || path == null) return;
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
