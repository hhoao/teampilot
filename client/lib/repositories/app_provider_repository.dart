import 'dart:convert';

import '../models/app_provider_config.dart';
import '../models/llm_config.dart';
import '../services/app_storage.dart';
import '../services/io/filesystem.dart';
import '../services/tool_config_generator.dart';

class AppProviderRepositoryException implements Exception {
  AppProviderRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppProviderRepository {
  AppProviderRepository({
    String? basePath,
    ToolConfigGenerator? generator,
    Filesystem? fs,
  }) : _basePathOverride = basePath,
       _generator = generator ?? const ToolConfigGenerator(),
       _fsOverride = fs;

  final String? _basePathOverride;
  final Filesystem? _fsOverride;
  final ToolConfigGenerator _generator;

  String get _basePath => _basePathOverride ?? AppStorage.paths.basePath;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;

  String providersPath(AppProviderCli cli) =>
      _fs.pathContext.join(_basePath, 'providers', cli.value, 'providers.json');

  String get _appFlashskyaiLlmConfigFile => _fs.pathContext.join(
    _basePath,
    'config-profiles',
    'flashskyai',
    'llm_config.json',
  );

  Future<List<AppProviderConfig>> loadProviders(AppProviderCli cli) async {
    final path = providersPath(cli);
    if (!(await _fs.stat(path)).isFile) return const [];
    try {
      final raw = await _fs.readString(path);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      return _decodeCatalog(cli, Map<String, Object?>.from(decoded));
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  Future<void> saveProviders(
    AppProviderCli cli,
    List<AppProviderConfig> providers,
  ) async {
    final path = providersPath(cli);
    await _fs.ensureDir(_fs.pathContext.dirname(path));

    final previous = await loadProviders(cli);
    final previousById = {for (final p in previous) p.id: p};
    final merged = [
      for (final provider in providers)
        _mergePreservedSecrets(
          provider.copyWith(cli: cli),
          previousById[provider.id],
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));

    final encoded = <String, Object?>{
      for (final provider in merged) provider.id: provider.toJson(),
    };

    final unknownTopLevel = await _loadUnknownTopLevel(path);
    unknownTopLevel.remove('providers');

    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent(
        '  ',
      ).convert({...unknownTopLevel, 'providers': encoded}),
    );

    switch (cli) {
      case AppProviderCli.codex:
        await _writeCodexNativeToolConfigs(merged);
        await _removeStaleCodexNativeToolConfigs(merged);
      case AppProviderCli.flashskyai:
        await _writeCommonFlashskyaiLlmConfig(merged);
      case AppProviderCli.claude:
        break;
    }
  }

  Future<AppProviderConfig?> findById(AppProviderCli cli, String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    final all = await loadProviders(cli);
    for (final provider in all) {
      if (provider.id == trimmed) return provider;
    }
    return null;
  }

  static AppProviderConfig _mergePreservedSecrets(
    AppProviderConfig provider,
    AppProviderConfig? previous,
  ) {
    if (previous == null) return provider;
    if (provider.apiKey.isNotEmpty || previous.apiKey.isEmpty) {
      return provider;
    }
    return provider.copyWith(apiKey: previous.apiKey);
  }

  Future<void> _writeCodexNativeToolConfigs(
    List<AppProviderConfig> providers,
  ) async {
    final path = _fs.pathContext;
    final root = path.join(_basePath, 'providers', 'codex');
    for (final provider in providers) {
      final codexDir = path.join(root, provider.id);
      await _fs.ensureDir(codexDir);
      await _generator.writeJsonAtomic(
        path.join(codexDir, 'auth.json'),
        _generator.buildCodexAuth(provider),
        fs: _fs,
      );
      final toml = _generator.buildCodexConfigToml(provider);
      final error = _generator.validateCodexToml(toml);
      if (error != null) {
        throw AppProviderRepositoryException(
          'Codex config.toml invalid for ${provider.id}: $error',
        );
      }
      if (toml.trim().isNotEmpty) {
        await _generator.writeTextAtomic(
          path.join(codexDir, 'config.toml'),
          toml,
          fs: _fs,
        );
      } else {
        await _deleteIfExists(path.join(codexDir, 'config.toml'));
      }
    }
  }

  Future<void> _removeStaleCodexNativeToolConfigs(
    List<AppProviderConfig> providers,
  ) async {
    final path = _fs.pathContext;
    final expected = providers.map((p) => p.id).toSet();
    final root = path.join(_basePath, 'providers', 'codex');
    if (!(await _fs.stat(root)).isDirectory) return;
    for (final entry in await _fs.listDir(root)) {
      if (!entry.isDirectory) continue;
      if (!expected.contains(entry.name)) {
        await _fs.removeRecursive(path.join(root, entry.name));
      }
    }
  }

  Future<void> _writeCommonFlashskyaiLlmConfig(
    List<AppProviderConfig> providers,
  ) async {
    final mergedProviders = <String, LlmProviderConfig>{};
    final mergedModels = <String, LlmModelConfig>{};
    final unknownFields = <String, Object?>{};

    for (final provider in providers) {
      final llm = _generator.buildFlashskyaiLlmConfig(provider);
      mergedProviders.addAll(llm.providers);
      mergedModels.addAll(llm.models);
      unknownFields.addAll(llm.unknownFields);
    }

    final config = LlmConfig(
      providers: mergedProviders,
      models: mergedModels,
      unknownFields: unknownFields,
    );

    await _generator.writeJsonAtomic(
      _appFlashskyaiLlmConfigFile,
      config.toJson(),
      fs: _fs,
    );
  }

  Future<void> _deleteIfExists(String path) async {
    if ((await _fs.stat(path)).exists) {
      await _fs.removeRecursive(path);
    }
  }

  List<AppProviderConfig> _decodeCatalog(
    AppProviderCli cli,
    Map<String, Object?> json,
  ) {
    final raw = json['providers'];
    if (raw is! Map) return const [];

    final providers = <AppProviderConfig>[];
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final map = Map<String, Object?>.from(entry.value as Map);
      map.putIfAbsent('id', () => entry.key as String);
      map['cli'] = cli.value;
      providers.add(AppProviderConfig.fromJson(map, cliFallback: cli));
    }
    providers.sort((a, b) => a.name.compareTo(b.name));
    return providers;
  }

  Future<Map<String, Object?>> _loadUnknownTopLevel(String path) async {
    if (!(await _fs.stat(path)).isFile) return {};
    try {
      final raw = await _fs.readString(path);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key != 'providers') entry.key: entry.value,
      };
    } on Object {
      return {};
    }
  }
}
