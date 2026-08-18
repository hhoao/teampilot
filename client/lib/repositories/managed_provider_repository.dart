import 'dart:convert';

import '../models/managed_provider.dart';
import '../services/io/filesystem.dart';
import '../services/storage/app_storage.dart';
import 'managed_provider_id_deletion_barrier.dart';
import 'managed_provider_storage_lock.dart';

/// Persists the CLI-independent managed provider catalog.
///
/// The required deletion cleanup boundary receives all IDs removed by one
/// mutation and is awaited before the configuration write. A cleanup failure
/// therefore leaves the provider configuration intact. If the later atomic
/// configuration write fails, that error is propagated; cleanup cannot be
/// rolled back, so callers should treat such a failure as requiring
/// reconciliation.
class ManagedProviderRepository {
  ManagedProviderRepository({
    Filesystem? fs,
    String? configPath,
    required Future<void> Function(List<String> providerIds) onProvidersDeleted,
  }) : _fsOverride = fs,
       _configPathOverride = configPath,
       _onProvidersDeleted = onProvidersDeleted;

  final Filesystem? _fsOverride;
  final String? _configPathOverride;
  final Future<void> Function(List<String> providerIds) _onProvidersDeleted;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;

  String get _configPath =>
      _configPathOverride ?? AppStorage.paths.managedProviderConfigFile;

  Future<List<ManagedProvider>> load() async {
    final store = await _readStore();
    return store.providers.values.toList(growable: false);
  }

  Future<void> save(List<ManagedProvider> providers) async {
    await ManagedProviderStorageLock.run(_configPath, () async {
      final current = await _readStore();
      final merged = <String, ManagedProvider>{};
      for (final provider in providers) {
        final normalized = _normalizeProvider(provider);
        if (normalized == null) continue;
        final previous = current.providers[normalized.id];
        merged[normalized.id] = previous == null
            ? normalized
            : _mergeProvider(previous, normalized);
      }
      final removedIds = {
        ...current.providers.keys,
        ...current.rawProviderEntries.keys
            .map((key) => key.trim())
            .where((id) => id.isNotEmpty),
      }.where((id) => !merged.containsKey(id)).toList()..sort();
      Future<void> write() async {
        await _writeStore(
          current.copyWith(providers: merged, rawProviderEntries: {}),
        );
      }

      if (removedIds.isEmpty) {
        await write();
      } else {
        await ManagedProviderIdDeletionBarrier.runDeletion(
          removedIds,
          () async {
            await _onProvidersDeleted(removedIds);
            await write();
          },
        );
      }
    });
  }

  Future<void> upsert(ManagedProvider provider) async {
    final normalized = _normalizeProvider(provider);
    if (normalized == null) return;
    await ManagedProviderStorageLock.run(_configPath, () async {
      final current = await _readStore();
      final previous = current.providers[normalized.id];
      final providers = Map<String, ManagedProvider>.from(current.providers);
      providers[normalized.id] = previous == null
          ? normalized
          : _mergeProvider(previous, normalized);
      final rawProviderEntries = Map<String, Object?>.from(
        current.rawProviderEntries,
      )..remove(normalized.id);
      await _writeStore(
        current.copyWith(
          providers: providers,
          rawProviderEntries: rawProviderEntries,
        ),
      );
    });
  }

  Future<void> delete(String providerId) async {
    final id = providerId.trim();
    if (id.isEmpty) return;
    await ManagedProviderStorageLock.run(_configPath, () async {
      final current = await _readStore();
      final hasRawEntry = current.rawProviderEntries.keys.any(
        (key) => key.trim() == id,
      );
      if (!current.providers.containsKey(id) && !hasRawEntry) return;
      final providers = Map<String, ManagedProvider>.from(current.providers)
        ..remove(id);
      final rawProviderEntries = Map<String, Object?>.from(
        current.rawProviderEntries,
      )..removeWhere((key, _) => key.trim() == id);
      await ManagedProviderIdDeletionBarrier.runDeletion([id], () async {
        await _onProvidersDeleted([id]);
        await _writeStore(
          current.copyWith(
            providers: providers,
            rawProviderEntries: rawProviderEntries,
          ),
        );
      });
    });
  }

  Future<_ManagedProviderStore> _readStore() async {
    final raw = await _fs.readString(_configPath);
    if (raw == null || raw.trim().isEmpty) {
      return const _ManagedProviderStore();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const _ManagedProviderStore();
      final json = Map<String, Object?>.from(decoded);
      final rawProviders = json['providers'];
      final providers = <String, ManagedProvider>{};
      final rawProviderEntries = <String, Object?>{};
      if (rawProviders is Map) {
        for (final entry in rawProviders.entries) {
          final id = entry.key;
          final value = entry.value;
          if (id is! String) continue;
          final normalizedId = id.trim();
          if (normalizedId.isEmpty) continue;
          if (value is! Map) {
            rawProviderEntries[normalizedId] = _sanitizeRawEntry(value);
            continue;
          }
          final providerJson = Map<String, Object?>.from(value);
          providerJson.putIfAbsent('id', () => normalizedId);
          try {
            final provider = ManagedProvider.fromJson(providerJson);
            providers[normalizedId] = provider.copyWith(id: normalizedId);
          } on Object {
            rawProviderEntries[normalizedId] = _sanitizeRawEntry(value);
          }
        }
      }
      return _ManagedProviderStore(
        providers: providers,
        rawProviderEntries: {
          for (final entry in rawProviderEntries.entries)
            if (!providers.containsKey(entry.key)) entry.key: entry.value,
        },
        schemaVersion: json.containsKey('schemaVersion')
            ? json['schemaVersion']
            : 1,
        unknownFields: _sanitizeDocumentFields({
          for (final entry in json.entries)
            if (entry.key != 'providers' && entry.key != 'schemaVersion')
              entry.key: entry.value,
        }),
      );
    } on Object {
      return const _ManagedProviderStore();
    }
  }

  Future<void> _writeStore(_ManagedProviderStore store) async {
    final path = _configPath;
    await _fs.ensureDir(_fs.pathContext.dirname(path));
    final providers = <String, Object?>{...store.rawProviderEntries};
    for (final id in store.providers.keys.toList()..sort()) {
      providers[id] = store.providers[id]!.toJson();
    }
    final json = <String, Object?>{
      ...store.unknownFields,
      'schemaVersion': store.schemaVersion,
      'providers': providers,
    };
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(json),
    );
  }

  static ManagedProvider? _normalizeProvider(ManagedProvider provider) {
    final id = provider.id.trim();
    if (id.isEmpty) return null;
    return provider.copyWith(id: id);
  }

  static Object? _sanitizeRawEntry(Object? value) {
    const rawField = '__managedProviderRawEntry';
    final holder = ManagedProvider(
      id: rawField,
      name: rawField,
      kind: ManagedProviderKind.unknown,
      adapterId: rawField,
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

  static ManagedProvider _mergeProvider(
    ManagedProvider previous,
    ManagedProvider next,
  ) => next.copyWith(
    schemaVersion: previous.schemaVersion >= next.schemaVersion
        ? previous.schemaVersion
        : next.schemaVersion,
    brand: ManagedProviderBrand(
      name: next.brand.name,
      iconUrl: next.brand.iconUrl,
      iconColor: next.brand.iconColor,
      unknownFields: {
        ...previous.brand.unknownFields,
        ...next.brand.unknownFields,
      },
    ),
    endpointConfig: ManagedProviderEndpointConfig(
      url: next.endpointConfig.url,
      method: next.endpointConfig.method,
      responsePath: next.endpointConfig.responsePath,
      measuresPath: next.endpointConfig.measuresPath,
      fieldMappings: {
        ...previous.endpointConfig.fieldMappings,
        ...next.endpointConfig.fieldMappings,
      },
      unknownFields: {
        ...previous.endpointConfig.unknownFields,
        ...next.endpointConfig.unknownFields,
      },
    ),
    displayConfig: ManagedProviderDisplayConfig(
      currency: next.displayConfig.currency,
      unit: next.displayConfig.unit,
      decimalPlaces: next.displayConfig.decimalPlaces,
      showPercent: next.displayConfig.showPercent,
      unknownFields: {
        ...previous.displayConfig.unknownFields,
        ...next.displayConfig.unknownFields,
      },
    ),
    unknownFields: {...previous.unknownFields, ...next.unknownFields},
  );
}

class _ManagedProviderStore {
  const _ManagedProviderStore({
    this.providers = const {},
    this.rawProviderEntries = const {},
    this.schemaVersion = 1,
    this.unknownFields = const {},
  });

  final Map<String, ManagedProvider> providers;
  final Map<String, Object?> rawProviderEntries;
  final Object? schemaVersion;
  final Map<String, Object?> unknownFields;

  _ManagedProviderStore copyWith({
    Map<String, ManagedProvider>? providers,
    Map<String, Object?>? rawProviderEntries,
    Object? schemaVersion,
    Map<String, Object?>? unknownFields,
  }) => _ManagedProviderStore(
    providers: providers ?? this.providers,
    rawProviderEntries: rawProviderEntries ?? this.rawProviderEntries,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    unknownFields: unknownFields ?? this.unknownFields,
  );
}
