import 'dart:convert';

import '../models/managed_provider.dart';
import '../services/io/filesystem.dart';
import '../services/storage/app_storage.dart';

/// Persists the CLI-independent managed provider catalog.
class ManagedProviderRepository {
  ManagedProviderRepository({Filesystem? fs, String? configPath})
    : _fsOverride = fs,
      _configPathOverride = configPath;

  final Filesystem? _fsOverride;
  final String? _configPathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;

  String get _configPath =>
      _configPathOverride ?? AppStorage.paths.managedProviderConfigFile;

  Future<List<ManagedProvider>> load() async {
    final store = await _readStore();
    return store.providers.values.toList(growable: false);
  }

  Future<void> save(List<ManagedProvider> providers) async {
    final current = await _readStore();
    final merged = <String, ManagedProvider>{};
    for (final provider in providers) {
      final previous = current.providers[provider.id];
      merged[provider.id] = previous == null
          ? provider
          : provider.copyWith(
              unknownFields: {
                ...previous.unknownFields,
                ...provider.unknownFields,
              },
            );
    }
    await _writeStore(current.copyWith(providers: merged));
  }

  Future<void> upsert(ManagedProvider provider) async {
    final current = await _readStore();
    final previous = current.providers[provider.id];
    final providers = Map<String, ManagedProvider>.from(current.providers);
    providers[provider.id] = previous == null
        ? provider
        : provider.copyWith(
            unknownFields: {
              ...previous.unknownFields,
              ...provider.unknownFields,
            },
          );
    await _writeStore(current.copyWith(providers: providers));
  }

  Future<void> delete(String providerId) async {
    final id = providerId.trim();
    if (id.isEmpty) return;
    final current = await _readStore();
    final providers = Map<String, ManagedProvider>.from(current.providers)
      ..remove(id);
    await _writeStore(current.copyWith(providers: providers));
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
      if (rawProviders is Map) {
        for (final entry in rawProviders.entries) {
          final id = entry.key;
          final value = entry.value;
          if (id is! String || value is! Map) continue;
          final providerJson = Map<String, Object?>.from(value);
          providerJson.putIfAbsent('id', () => id);
          try {
            final provider = ManagedProvider.fromJson(providerJson);
            if (provider.id.trim().isNotEmpty) {
              providers[provider.id] = provider;
            }
          } on Object {
            // One malformed provider must not hide the valid catalog entries.
          }
        }
      }
      return _ManagedProviderStore(
        providers: providers,
        unknownFields: {
          for (final entry in json.entries)
            if (entry.key != 'providers' && entry.key != 'schemaVersion')
              entry.key: entry.value,
        },
      );
    } on Object {
      return const _ManagedProviderStore();
    }
  }

  Future<void> _writeStore(_ManagedProviderStore store) async {
    final path = _configPath;
    await _fs.ensureDir(_fs.pathContext.dirname(path));
    final providers = <String, Object?>{};
    for (final id in store.providers.keys.toList()..sort()) {
      providers[id] = store.providers[id]!.toJson();
    }
    final json = <String, Object?>{
      ...store.unknownFields,
      'schemaVersion': 1,
      'providers': providers,
    };
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(json),
    );
  }
}

class _ManagedProviderStore {
  const _ManagedProviderStore({
    this.providers = const {},
    this.unknownFields = const {},
  });

  final Map<String, ManagedProvider> providers;
  final Map<String, Object?> unknownFields;

  _ManagedProviderStore copyWith({
    Map<String, ManagedProvider>? providers,
    Map<String, Object?>? unknownFields,
  }) => _ManagedProviderStore(
    providers: providers ?? this.providers,
    unknownFields: unknownFields ?? this.unknownFields,
  );
}
