import 'dart:convert';

import '../models/provider_usage_snapshot.dart';
import '../services/io/filesystem.dart';
import '../services/storage/app_storage.dart';

/// Persists normalized usage snapshots independently from provider config.
class ManagedProviderUsageRepository {
  ManagedProviderUsageRepository({
    Filesystem? fs,
    String? cachePath,
    int Function()? now,
  }) : _fsOverride = fs,
       _cachePathOverride = cachePath,
       _now = now ?? _epochMilliseconds;

  final Filesystem? _fsOverride;
  final String? _cachePathOverride;
  final int Function() _now;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;

  String get _cachePath =>
      _cachePathOverride ?? AppStorage.paths.managedProviderUsageCacheFile;

  Future<List<ProviderUsageSnapshot>> load() async {
    final store = await _readStore();
    final now = _now();
    return [
      for (final snapshot in store.snapshots.values)
        snapshot.staleAt != null && now >= snapshot.staleAt!
            ? snapshot.copyWith(status: ProviderUsageStatus.stale)
            : snapshot,
    ];
  }

  Future<void> save(ProviderUsageSnapshot snapshot) async {
    final current = await _readStore();
    final previous = current.snapshots[snapshot.providerId];
    final snapshots = Map<String, ProviderUsageSnapshot>.from(
      current.snapshots,
    );
    snapshots[snapshot.providerId] = previous == null
        ? snapshot
        : snapshot.copyWith(
            unknownFields: {
              ...previous.unknownFields,
              ...snapshot.unknownFields,
            },
          );
    await _writeStore(current.copyWith(snapshots: snapshots));
  }

  Future<void> delete(String providerId) async {
    final id = providerId.trim();
    if (id.isEmpty) return;
    final current = await _readStore();
    final snapshots = Map<String, ProviderUsageSnapshot>.from(current.snapshots)
      ..remove(id);
    await _writeStore(current.copyWith(snapshots: snapshots));
  }

  Future<void> clear() async {
    final current = await _readStore();
    await _writeStore(current.copyWith(snapshots: {}));
  }

  Future<_ManagedProviderUsageStore> _readStore() async {
    final raw = await _fs.readString(_cachePath);
    if (raw == null || raw.trim().isEmpty) {
      return const _ManagedProviderUsageStore();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const _ManagedProviderUsageStore();
      final json = Map<String, Object?>.from(decoded);
      final rawSnapshots = json['snapshots'];
      final snapshots = <String, ProviderUsageSnapshot>{};
      if (rawSnapshots is Map) {
        for (final entry in rawSnapshots.entries) {
          final id = entry.key;
          final value = entry.value;
          if (id is! String || value is! Map) continue;
          final snapshotJson = Map<String, Object?>.from(value);
          snapshotJson.putIfAbsent('providerId', () => id);
          try {
            final snapshot = ProviderUsageSnapshot.fromJson(snapshotJson);
            if (snapshot.providerId.trim().isNotEmpty) {
              snapshots[snapshot.providerId] = snapshot;
            }
          } on Object {
            // One malformed snapshot must not hide the valid cache entries.
          }
        }
      }
      return _ManagedProviderUsageStore(
        snapshots: snapshots,
        unknownFields: {
          for (final entry in json.entries)
            if (entry.key != 'snapshots' && entry.key != 'schemaVersion')
              entry.key: entry.value,
        },
      );
    } on Object {
      return const _ManagedProviderUsageStore();
    }
  }

  Future<void> _writeStore(_ManagedProviderUsageStore store) async {
    final path = _cachePath;
    await _fs.ensureDir(_fs.pathContext.dirname(path));
    final snapshots = <String, Object?>{};
    for (final id in store.snapshots.keys.toList()..sort()) {
      snapshots[id] = store.snapshots[id]!.toJson();
    }
    final json = <String, Object?>{
      ...store.unknownFields,
      'schemaVersion': 1,
      'snapshots': snapshots,
    };
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(json),
    );
  }

  static int _epochMilliseconds() => DateTime.now().millisecondsSinceEpoch;
}

class _ManagedProviderUsageStore {
  const _ManagedProviderUsageStore({
    this.snapshots = const {},
    this.unknownFields = const {},
  });

  final Map<String, ProviderUsageSnapshot> snapshots;
  final Map<String, Object?> unknownFields;

  _ManagedProviderUsageStore copyWith({
    Map<String, ProviderUsageSnapshot>? snapshots,
    Map<String, Object?>? unknownFields,
  }) => _ManagedProviderUsageStore(
    snapshots: snapshots ?? this.snapshots,
    unknownFields: unknownFields ?? this.unknownFields,
  );
}
