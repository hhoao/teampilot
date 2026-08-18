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
    final normalized = _normalizeSnapshot(snapshot);
    if (normalized == null) return;
    final current = await _readStore();
    final previous = current.snapshots[normalized.providerId];
    final snapshots = Map<String, ProviderUsageSnapshot>.from(
      current.snapshots,
    );
    snapshots[normalized.providerId] = previous == null
        ? normalized
        : _mergeSnapshot(previous, normalized);
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
          final normalizedId = id.trim();
          if (normalizedId.isEmpty) continue;
          final snapshotJson = Map<String, Object?>.from(value);
          snapshotJson.putIfAbsent('providerId', () => normalizedId);
          try {
            final snapshot = ProviderUsageSnapshot.fromJson(snapshotJson);
            snapshots[normalizedId] = snapshot.copyWith(
              providerId: normalizedId,
            );
          } on Object {
            // One malformed snapshot must not hide the valid cache entries.
          }
        }
      }
      return _ManagedProviderUsageStore(
        snapshots: snapshots,
        schemaVersion: json.containsKey('schemaVersion')
            ? json['schemaVersion']
            : 1,
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
      'schemaVersion': store.schemaVersion,
      'snapshots': snapshots,
    };
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(json),
    );
  }

  static int _epochMilliseconds() => DateTime.now().millisecondsSinceEpoch;

  static ProviderUsageSnapshot? _normalizeSnapshot(
    ProviderUsageSnapshot snapshot,
  ) {
    final providerId = snapshot.providerId.trim();
    if (providerId.isEmpty) return null;
    return snapshot.copyWith(providerId: providerId);
  }

  static ProviderUsageSnapshot _mergeSnapshot(
    ProviderUsageSnapshot previous,
    ProviderUsageSnapshot next,
  ) {
    final measures = <ProviderUsageMeasure>[];
    final usedPrevious = <int>{};
    for (final measure in next.measures) {
      var previousIndex = -1;
      for (var i = 0; i < previous.measures.length; i++) {
        final candidate = previous.measures[i];
        if (usedPrevious.contains(i) ||
            candidate.label != measure.label ||
            candidate.kind != measure.kind) {
          continue;
        }
        previousIndex = i;
        break;
      }
      if (previousIndex < 0) {
        measures.add(measure);
        continue;
      }
      usedPrevious.add(previousIndex);
      final previousMeasure = previous.measures[previousIndex];
      measures.add(
        measure.copyWith(
          unknownFields: {
            ...previousMeasure.unknownFields,
            ...measure.unknownFields,
          },
        ),
      );
    }
    return next.copyWith(
      schemaVersion: previous.schemaVersion >= next.schemaVersion
          ? previous.schemaVersion
          : next.schemaVersion,
      measures: measures,
      unknownFields: {...previous.unknownFields, ...next.unknownFields},
    );
  }
}

class _ManagedProviderUsageStore {
  const _ManagedProviderUsageStore({
    this.snapshots = const {},
    this.schemaVersion = 1,
    this.unknownFields = const {},
  });

  final Map<String, ProviderUsageSnapshot> snapshots;
  final Object? schemaVersion;
  final Map<String, Object?> unknownFields;

  _ManagedProviderUsageStore copyWith({
    Map<String, ProviderUsageSnapshot>? snapshots,
    Object? schemaVersion,
    Map<String, Object?>? unknownFields,
  }) => _ManagedProviderUsageStore(
    snapshots: snapshots ?? this.snapshots,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    unknownFields: unknownFields ?? this.unknownFields,
  );
}
