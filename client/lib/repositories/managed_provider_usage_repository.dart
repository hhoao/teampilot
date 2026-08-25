import 'dart:convert';

import '../models/provider_usage_snapshot.dart';
import '../services/io/filesystem.dart';
import '../services/storage/app_storage.dart';
import 'managed_provider_id_deletion_barrier.dart';
import 'managed_provider_storage_lock.dart';

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
    return store.snapshots.values.toList(growable: false);
  }

  Future<void> save(ProviderUsageSnapshot snapshot) async {
    final normalized = _normalizeSnapshot(snapshot);
    if (normalized == null) return;
    await ManagedProviderIdDeletionBarrier.runUsageMutation(
      normalized.providerId,
      () async {
        await ManagedProviderStorageLock.run(_cachePath, () async {
          final current = await _readStore();
          final previous = current.snapshots[normalized.providerId];
          final snapshots = Map<String, ProviderUsageSnapshot>.from(
            current.snapshots,
          );
          snapshots[normalized.providerId] = previous == null
              ? normalized
              : _mergeSnapshot(previous, normalized);
          final rawSnapshotEntries = Map<String, Object?>.from(
            current.rawSnapshotEntries,
          )..remove(normalized.providerId);
          await _writeStore(
            current.copyWith(
              snapshots: snapshots,
              rawSnapshotEntries: rawSnapshotEntries,
            ),
          );
        });
      },
    );
  }

  /// Conditionally persists a snapshot while holding the same cache lock as
  /// [save]. The predicate is evaluated immediately before the atomic write;
  /// false means no cache write occurred.
  Future<bool> saveIf(
    ProviderUsageSnapshot snapshot, {
    required bool Function() shouldCommit,
  }) async {
    final normalized = _normalizeSnapshot(snapshot);
    if (normalized == null) return false;
    return ManagedProviderIdDeletionBarrier.runConditionalUsageMutation(
      normalized.providerId,
      () async {
        return ManagedProviderStorageLock.run(_cachePath, () async {
          final current = await _readStore();
          final previous = current.snapshots[normalized.providerId];
          final snapshots = Map<String, ProviderUsageSnapshot>.from(
            current.snapshots,
          );
          snapshots[normalized.providerId] = previous == null
              ? normalized
              : _mergeSnapshot(previous, normalized);
          final rawSnapshotEntries = Map<String, Object?>.from(
            current.rawSnapshotEntries,
          )..remove(normalized.providerId);
          return _writeStore(
            current.copyWith(
              snapshots: snapshots,
              rawSnapshotEntries: rawSnapshotEntries,
            ),
            shouldCommit: shouldCommit,
          );
        });
      },
      blockedResult: false,
    );
  }

  Future<void> delete(String providerId) => deleteMany([providerId]);

  Future<void> deleteMany(Iterable<String> providerIds) async {
    final ids = providerIds
        .map((providerId) => providerId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return;
    await ManagedProviderStorageLock.run(_cachePath, () async {
      final current = await _readStore();
      final hasMatchingEntry = ids.any(
        (id) =>
            current.snapshots.containsKey(id) ||
            current.rawSnapshotEntries.containsKey(id),
      );
      if (!hasMatchingEntry) return;
      final snapshots = Map<String, ProviderUsageSnapshot>.from(
        current.snapshots,
      )..removeWhere((id, _) => ids.contains(id));
      final rawSnapshotEntries = Map<String, Object?>.from(
        current.rawSnapshotEntries,
      )..removeWhere((id, _) => ids.contains(id));
      await _writeStore(
        current.copyWith(
          snapshots: snapshots,
          rawSnapshotEntries: rawSnapshotEntries,
        ),
      );
    });
  }

  Future<void> clear() async {
    await ManagedProviderStorageLock.run(_cachePath, () async {
      final current = await _readStore();
      await _writeStore(
        current.copyWith(snapshots: {}, rawSnapshotEntries: {}),
      );
    });
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
      final rawSnapshotEntries = <String, Object?>{};
      if (rawSnapshots is Map) {
        for (final entry in rawSnapshots.entries) {
          final id = entry.key;
          final value = entry.value;
          if (id is! String) continue;
          final normalizedId = id.trim();
          if (normalizedId.isEmpty) continue;
          if (value is! Map) {
            rawSnapshotEntries[normalizedId] = _sanitizeRawEntry(value);
            continue;
          }
          final snapshotJson = Map<String, Object?>.from(value);
          snapshotJson.putIfAbsent('providerId', () => normalizedId);
          try {
            final snapshot = ProviderUsageSnapshot.fromJson(snapshotJson);
            snapshots[normalizedId] = snapshot.copyWith(
              providerId: normalizedId,
            );
          } on Object {
            rawSnapshotEntries[normalizedId] = _sanitizeRawEntry(value);
          }
        }
      }
      return _ManagedProviderUsageStore(
        snapshots: snapshots,
        rawSnapshotEntries: {
          for (final entry in rawSnapshotEntries.entries)
            if (!snapshots.containsKey(entry.key)) entry.key: entry.value,
        },
        schemaVersion: json.containsKey('schemaVersion')
            ? json['schemaVersion']
            : 1,
        unknownFields: _sanitizeDocumentFields({
          for (final entry in json.entries)
            if (entry.key != 'snapshots' && entry.key != 'schemaVersion')
              entry.key: entry.value,
        }),
      );
    } on Object {
      return const _ManagedProviderUsageStore();
    }
  }

  Future<bool> _writeStore(
    _ManagedProviderUsageStore store, {
    bool Function()? shouldCommit,
  }) async {
    final path = _cachePath;
    await _fs.ensureDir(_fs.pathContext.dirname(path));
    final snapshots = <String, Object?>{...store.rawSnapshotEntries};
    for (final id in store.snapshots.keys.toList()..sort()) {
      snapshots[id] = store.snapshots[id]!.toJson();
    }
    final json = <String, Object?>{
      ...store.unknownFields,
      'schemaVersion': store.schemaVersion,
      'snapshots': snapshots,
    };
    if (shouldCommit != null && !shouldCommit()) return false;
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(json),
    );
    return true;
  }

  static int _epochMilliseconds() => DateTime.now().millisecondsSinceEpoch;

  static ProviderUsageSnapshot? _normalizeSnapshot(
    ProviderUsageSnapshot snapshot,
  ) {
    final providerId = snapshot.providerId.trim();
    if (providerId.isEmpty) return null;
    return snapshot.copyWith(providerId: providerId);
  }

  static Object? _sanitizeRawEntry(Object? value) {
    const rawField = '__managedProviderUsageRawEntry';
    final holder = ProviderUsageSnapshot(
      providerId: rawField,
      status: ProviderUsageStatus.unknown,
      unknownFields: {rawField: value},
    );
    return holder.unknownFields[rawField];
  }

  static Map<String, Object?> _sanitizeDocumentFields(
    Map<String, Object?> fields,
  ) {
    final sanitized = _sanitizeRawEntry(fields);
    return sanitized is Map ? Map<String, Object?>.from(sanitized) : const {};
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
    this.rawSnapshotEntries = const {},
    this.schemaVersion = 1,
    this.unknownFields = const {},
  });

  final Map<String, ProviderUsageSnapshot> snapshots;
  final Map<String, Object?> rawSnapshotEntries;
  final Object? schemaVersion;
  final Map<String, Object?> unknownFields;

  _ManagedProviderUsageStore copyWith({
    Map<String, ProviderUsageSnapshot>? snapshots,
    Map<String, Object?>? rawSnapshotEntries,
    Object? schemaVersion,
    Map<String, Object?>? unknownFields,
  }) => _ManagedProviderUsageStore(
    snapshots: snapshots ?? this.snapshots,
    rawSnapshotEntries: rawSnapshotEntries ?? this.rawSnapshotEntries,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    unknownFields: unknownFields ?? this.unknownFields,
  );
}
