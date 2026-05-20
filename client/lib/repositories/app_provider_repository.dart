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
  AppProviderRepository({File? providersFile, ToolConfigGenerator? generator})
    : providersFile =
          providersFile ?? File(p.join(AppStorage.providerConfigFile)),
      _generator = generator ?? const ToolConfigGenerator();

  final File providersFile;
  final ToolConfigGenerator _generator;

  static File providersFileForBasePath(String basePath) {
    return File(p.join(basePath, 'providers', 'providers.json'));
  }

  String get _appDataBasePath {
    // providers/providers.json -> <basePath>
    return providersFile.parent.parent.path;
  }

  String get _commonFlashskyaiLlmConfigFile => p.join(
    _appDataBasePath,
    'config-profiles',
    'common',
    'flashskyai',
    'llm_config.json',
  );

  Future<List<AppProviderConfig>> loadProviders() async {
    final file = providersFile;
    if (!await file.exists()) {
      return const [];
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const [];
      return _decodeCatalog(Map<String, Object?>.from(decoded));
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  Future<void> saveProviders(List<AppProviderConfig> providers) async {
    final file = providersFile;
    await file.parent.create(recursive: true);

    final previous = await loadProviders();
    final previousById = {for (final p in previous) p.id: p};

    final merged = [
      for (final provider in providers)
        _mergePreservedSecrets(provider, previousById[provider.id]),
    ];

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

    await _writeNativeToolConfigs(merged);
    await _removeStaleNativeToolConfigs(merged);
    await _writeCommonFlashskyaiLlmConfig(merged);
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

  Future<AppProviderConfig?> findById(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    final all = await loadProviders();
    for (final provider in all) {
      if (provider.id == trimmed) return provider;
    }
    return null;
  }

  Future<void> _writeNativeToolConfigs(
    List<AppProviderConfig> providers,
  ) async {
    final root = providersFile.parent;
    for (final provider in providers) {
      if (provider.enables(AppProviderTool.codex)) {
        final codexDir = Directory(p.join(root.path, 'codex', provider.id));
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
    await _removeLegacyClaudeProviderDirs(providersFile.parent);
  }

  Future<void> _removeLegacyClaudeProviderDirs(Directory providersRoot) async {
    final claudeDir = Directory(p.join(providersRoot.path, 'claude'));
    if (await claudeDir.exists()) {
      await claudeDir.delete(recursive: true);
    }
  }

  Future<void> _removeStaleNativeToolConfigs(
    List<AppProviderConfig> providers,
  ) async {
    final expectedByTool = {
      AppProviderTool.codex.value: providers
          .where((p) => p.enables(AppProviderTool.codex))
          .map((p) => p.id)
          .toSet(),
    };

    final root = providersFile.parent;
    for (final entry in expectedByTool.entries) {
      final toolDir = Directory(p.join(root.path, entry.key));
      if (!await toolDir.exists()) continue;
      await for (final entity in toolDir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final providerId = p.basename(entity.path);
        if (!entry.value.contains(providerId)) {
          await entity.delete(recursive: true);
        }
      }
    }
  }

  Future<void> _writeCommonFlashskyaiLlmConfig(
    List<AppProviderConfig> providers,
  ) async {
    final flashskyaiProviders = providers
        .where((p) => p.enables(AppProviderTool.flashskyai))
        .toList(growable: false);

    final mergedProviders = <String, LlmProviderConfig>{};
    final mergedModels = <String, LlmModelConfig>{};
    final unknownFields = <String, Object?>{};

    for (final provider in flashskyaiProviders) {
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
      File(_commonFlashskyaiLlmConfigFile),
      config.toJson(),
    );
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  List<AppProviderConfig> _decodeCatalog(Map<String, Object?> json) {
    final raw = json['providers'];
    if (raw is! Map) return const [];

    final providers = <AppProviderConfig>[];
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final map = Map<String, Object?>.from(entry.value as Map);
      map.putIfAbsent('id', () => entry.key as String);
      providers.add(AppProviderConfig.fromJson(map));
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
