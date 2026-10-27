import 'dart:convert';

import '../../utils/lock_pool.dart';
import '../cli/registry/capabilities/session_usage_capability.dart';
import '../io/filesystem.dart';
import 'usage_cursor_store.dart';

/// Whole-map JSON cursor file, written atomically.
class JsonUsageCursorStore implements UsageCursorStore {
  JsonUsageCursorStore({required Filesystem fs, required String filePath})
    : _fs = fs,
      _path = filePath;

  final Filesystem _fs;
  final String _path;
  final LockPool _locks = LockPool();

  Map<String, UsageCursor>? _cache;

  Future<Map<String, UsageCursor>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await _fs.readString(_path);
    final map = <String, UsageCursor>{};
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final value = entry.value;
            if (value is! Map) continue;
            map['${entry.key}'] = UsageCursor.fromJson(
              Map<String, Object?>.from(value),
            );
          }
        }
      } on Object {
        // Corrupt cursor file: start clean. Events are upserted idempotently.
      }
    }
    _cache = map;
    return map;
  }

  @override
  Future<UsageCursor?> read(String sourceId) async {
    final map = await _load();
    return map[sourceId];
  }

  @override
  Future<void> save(String sourceId, UsageCursor cursor) {
    return _mutate((map) => map[sourceId] = cursor);
  }

  @override
  Future<void> remove(String sourceId) {
    return _mutate((map) => map.remove(sourceId));
  }

  @override
  Future<int> prune(Set<String> activeSourceIds) {
    return _locks.synchronized(_path, () async {
      final current = await _load();
      final removed = current.keys
          .where((sourceId) => !activeSourceIds.contains(sourceId))
          .toList(growable: false);
      if (removed.isEmpty) return 0;
      final next = Map<String, UsageCursor>.of(current)
        ..removeWhere((sourceId, _) => !activeSourceIds.contains(sourceId));
      final encoded = {
        for (final entry in next.entries) entry.key: entry.value.toJson(),
      };
      await _fs.atomicWrite(
        _path,
        const JsonEncoder.withIndent('  ').convert(encoded),
      );
      _cache = next;
      return removed.length;
    });
  }

  Future<void> _mutate(void Function(Map<String, UsageCursor>) change) {
    return _locks.synchronized(_path, () async {
      final current = await _load();
      final next = Map<String, UsageCursor>.of(current);
      change(next);
      final encoded = {
        for (final entry in next.entries) entry.key: entry.value.toJson(),
      };
      await _fs.atomicWrite(
        _path,
        const JsonEncoder.withIndent('  ').convert(encoded),
      );
      _cache = next;
    });
  }
}
