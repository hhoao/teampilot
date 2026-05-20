import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_provider_config.dart';
import '../models/llm_config.dart';
import '../services/app_storage.dart';
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
  }) : _basePath = basePath ?? AppPathsBootstrapper.current.basePath,
       _generator = generator ?? const ToolConfigGenerator();

  final String _basePath;
  final ToolConfigGenerator _generator;

  /// Catalog for one CLI: `<basePath>/providers/<cli>/providers.json`.
  static File providersFileForBasePath(String basePath, AppProviderCli cli) {
    return File(p.join(basePath, 'providers', cli.value, 'providers.json'));
  }

  File providersFile(AppProviderCli cli) =>
      providersFileForBasePath(_basePath, cli);

  String get _appFlashskyaiLlmConfigFile =>
      p.join(_basePath, 'config-profiles', 'flashskyai', 'llm_config.json');

  Future<List<AppProviderConfig>> loadProviders(AppProviderCli cli) async {
    final file = providersFile(cli);
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
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
    final file = providersFile(cli);
    await file.parent.create(recursive: true);

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

    final unknownTopLevel = await _loadUnknownTopLevel(file);
    unknownTopLevel.remove('providers');

    await file.writeAsString(
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
    final root = Directory(p.join(_basePath, 'providers', 'codex'));
    for (final provider in providers) {
      final codexDir = Directory(p.join(root.path, provider.id));
      await codexDir.create(recursive: true);
      await _generator.writeJsonAtomic(
        File(p.join(codexDir.path, 'auth.json')),
        _generator.buildCodexAuth(provider),
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
          File(p.join(codexDir.path, 'config.toml')),
          toml,
        );
      } else {
        await _deleteIfExists(File(p.join(codexDir.path, 'config.toml')));
      }
    }
  }

  Future<void> _removeStaleCodexNativeToolConfigs(
    List<AppProviderConfig> providers,
  ) async {
    final expected = providers.map((p) => p.id).toSet();
    final root = Directory(p.join(_basePath, 'providers', 'codex'));
    if (!await root.exists()) return;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final providerId = p.basename(entity.path);
      if (!expected.contains(providerId)) {
        await entity.delete(recursive: true);
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
      File(_appFlashskyaiLlmConfigFile),
      config.toJson(),
    );
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
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

  Future<Map<String, Object?>> _loadUnknownTopLevel(File file) async {
    if (!await file.exists()) return {};
    try {
      final decoded = jsonDecode(await file.readAsString());
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
