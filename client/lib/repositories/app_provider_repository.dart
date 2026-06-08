import 'dart:convert';

import '../models/app_provider_config.dart';
import '../models/llm_config.dart';
import '../services/storage/app_storage.dart';
import '../services/provider/claude/claude_official_provider.dart';
import '../services/provider/claude/claude_provider_credentials_service.dart';
import '../services/provider/codex/codex_official_provider.dart';
import '../services/provider/codex/codex_provider_credentials_service.dart';
import '../services/provider/cursor/cursor_provider_credentials_service.dart';
import '../services/provider/opencode/opencode_provider_credentials_service.dart';
import '../services/io/filesystem.dart';
import '../services/provider/tool_config_generator.dart';

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
    ClaudeProviderCredentialsService? claudeCredentialsService,
    CursorProviderCredentialsService? cursorCredentialsService,
    CodexProviderCredentialsService? codexCredentialsService,
    OpencodeProviderCredentialsService? opencodeCredentialsService,
  }) : _basePathOverride = basePath,
       _generator = generator ?? const ToolConfigGenerator(),
       _fsOverride = fs,
       _claudeCredentialsServiceOverride = claudeCredentialsService,
       _cursorCredentialsServiceOverride = cursorCredentialsService,
       _codexCredentialsServiceOverride = codexCredentialsService,
       _opencodeCredentialsServiceOverride = opencodeCredentialsService;

  final String? _basePathOverride;
  final Filesystem? _fsOverride;
  final ToolConfigGenerator _generator;
  final ClaudeProviderCredentialsService? _claudeCredentialsServiceOverride;
  final CursorProviderCredentialsService? _cursorCredentialsServiceOverride;
  final CodexProviderCredentialsService? _codexCredentialsServiceOverride;
  final OpencodeProviderCredentialsService? _opencodeCredentialsServiceOverride;

  String get _basePath => _basePathOverride ?? AppStorage.paths.basePath;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;

  ClaudeProviderCredentialsService get _claudeCredentials =>
      _claudeCredentialsServiceOverride ??
      ClaudeProviderCredentialsService(fs: _fs, basePath: _basePath);

  CursorProviderCredentialsService get _cursorCredentials =>
      _cursorCredentialsServiceOverride ??
      CursorProviderCredentialsService(fs: _fs, basePath: _basePath);

  CodexProviderCredentialsService get _codexCredentials =>
      _codexCredentialsServiceOverride ??
      CodexProviderCredentialsService(fs: _fs, basePath: _basePath);

  OpencodeProviderCredentialsService get _opencodeCredentials =>
      _opencodeCredentialsServiceOverride ??
      OpencodeProviderCredentialsService(fs: _fs, basePath: _basePath);

  String providersPath(CliTool cli) =>
      _fs.pathContext.join(_basePath, 'providers', cli.value, 'providers.json');

  String get _appFlashskyaiLlmConfigFile => _fs.pathContext.join(
    _basePath,
    'config-profiles',
    'flashskyai',
    'llm_config.json',
  );

  Future<List<AppProviderConfig>> loadProviders(CliTool cli) async {
    final providers = await _loadProvidersFromDisk(cli);
    return switch (cli) {
      CliTool.claude => _probeClaudeCredentials(providers),
      CliTool.cursor => _probeCursorCredentials(providers),
      CliTool.codex => _probeCodexCredentials(providers),
      CliTool.opencode => _probeOpencodeCredentials(providers),
      _ => providers,
    };
  }

  Future<List<AppProviderConfig>> _loadProvidersFromDisk(
    CliTool cli,
  ) async {
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
    CliTool cli,
    List<AppProviderConfig> providers,
  ) async {
    final path = providersPath(cli);
    await _fs.ensureDir(_fs.pathContext.dirname(path));

    final previous = await _loadProvidersFromDisk(cli);
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
      case CliTool.codex:
        await _writeCodexNativeToolConfigs(merged);
        await _removeStaleCodexNativeToolConfigs(merged);
      case CliTool.flashskyai:
        await _writeCommonFlashskyaiLlmConfig(merged);
      case CliTool.claude:
        await _removeStaleClaudeNativeDirs(merged);
      case CliTool.opencode:
        break;
      case CliTool.cursor:
        await _removeStaleCursorNativeDirs(merged);
    }
  }

  Future<void> _removeStaleClaudeNativeDirs(
    List<AppProviderConfig> providers,
  ) async {
    final path = _fs.pathContext;
    final expected = providers.map((p) => p.id).toSet();
    final root = path.join(_basePath, 'providers', 'claude');
    if (!(await _fs.stat(root)).isDirectory) return;
    for (final entry in await _fs.listDir(root)) {
      if (!entry.isDirectory) continue;
      if (entry.name == 'providers.json') continue;
      if (!expected.contains(entry.name)) {
        await _fs.removeRecursive(path.join(root, entry.name));
      }
    }
  }

  Future<void> _removeStaleCursorNativeDirs(
    List<AppProviderConfig> providers,
  ) async {
    final path = _fs.pathContext;
    final expected = providers.map((p) => p.id).toSet();
    final root = path.join(_basePath, 'providers', 'cursor');
    if (!(await _fs.stat(root)).isDirectory) return;
    for (final entry in await _fs.listDir(root)) {
      if (!entry.isDirectory) continue;
      if (entry.name == 'providers.json') continue;
      if (!expected.contains(entry.name)) {
        await _fs.removeRecursive(path.join(root, entry.name));
      }
    }
  }

  Future<List<AppProviderConfig>> _probeClaudeCredentials(
    List<AppProviderConfig> providers,
  ) async {
    var changed = false;
    final probed = <AppProviderConfig>[];
    for (final provider in providers) {
      if (provider.cli != CliTool.claude ||
          !isOfficialClaudeSettings(provider.config)) {
        probed.add(provider);
        continue;
      }
      var probe = await _claudeCredentials.probe(provider.id);
      if (!probe.isReady) {
        final home = AppStorage.home.trim();
        if (home.isNotEmpty) {
          await _claudeCredentials.importFromGlobal(
            provider.id,
            homeDirectory: home,
            replace: false,
          );
          probe = await _claudeCredentials.probe(provider.id);
        }
      }
      final next = provider.withCredentialProbe(probe);
      if (next.credentialStatus != provider.credentialStatus ||
          next.credentialUpdatedAt != provider.credentialUpdatedAt) {
        changed = true;
      }
      probed.add(next);
    }
    if (changed) {
      await saveProviders(CliTool.claude, probed);
    }
    return probed;
  }

  Future<List<AppProviderConfig>> _probeCursorCredentials(
    List<AppProviderConfig> providers,
  ) async {
    var changed = false;
    final probed = <AppProviderConfig>[];
    for (final provider in providers) {
      if (provider.cli != CliTool.cursor || !provider.isOfficial) {
        probed.add(provider);
        continue;
      }
      var probe = await _cursorCredentials.probe(provider.id);
      if (!probe.isReady) {
        final home = AppStorage.home.trim();
        if (home.isNotEmpty) {
          await _cursorCredentials.importFromGlobal(
            provider.id,
            homeDirectory: home,
            replace: false,
          );
          probe = await _cursorCredentials.probe(provider.id);
        }
      }
      final next = provider.withCredentialProbe(probe);
      if (next.credentialStatus != provider.credentialStatus ||
          next.credentialUpdatedAt != provider.credentialUpdatedAt) {
        changed = true;
      }
      probed.add(next);
    }
    if (changed) {
      await saveProviders(CliTool.cursor, probed);
    }
    return probed;
  }

  Future<List<AppProviderConfig>> _probeCodexCredentials(
    List<AppProviderConfig> providers,
  ) async {
    var changed = false;
    final probed = <AppProviderConfig>[];
    for (final provider in providers) {
      if (!isOfficialCodexOAuthProvider(provider)) {
        probed.add(provider);
        continue;
      }
      var probe = await _codexCredentials.probe(provider.id);
      if (!probe.isReady) {
        final home = AppStorage.home.trim();
        if (home.isNotEmpty) {
          await _codexCredentials.importFromGlobal(
            provider.id,
            homeDirectory: home,
            replace: false,
          );
          probe = await _codexCredentials.probe(provider.id);
        }
      }
      final next = provider.withCredentialProbe(probe);
      if (next.credentialStatus != provider.credentialStatus ||
          next.credentialUpdatedAt != provider.credentialUpdatedAt) {
        changed = true;
      }
      probed.add(next);
    }
    if (changed) {
      await saveProviders(CliTool.codex, probed);
    }
    return probed;
  }

  Future<List<AppProviderConfig>> _probeOpencodeCredentials(
    List<AppProviderConfig> providers,
  ) async {
    var changed = false;
    final probed = <AppProviderConfig>[];
    for (final provider in providers) {
      if (provider.cli != CliTool.opencode || !provider.isOfficial) {
        probed.add(provider);
        continue;
      }
      var probe = await _opencodeCredentials.probe(provider.id);
      if (!probe.isReady) {
        final home = AppStorage.home.trim();
        if (home.isNotEmpty) {
          await _opencodeCredentials.importFromGlobal(
            provider.id,
            homeDirectory: home,
            replace: false,
          );
          probe = await _opencodeCredentials.probe(provider.id);
        }
      }
      final next = provider.withCredentialProbe(probe);
      if (next.credentialStatus != provider.credentialStatus ||
          next.credentialUpdatedAt != provider.credentialUpdatedAt) {
        changed = true;
      }
      probed.add(next);
    }
    if (changed) {
      await saveProviders(CliTool.opencode, probed);
    }
    return probed;
  }

  Future<AppProviderConfig?> findById(CliTool cli, String id) async {
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
      final authPath = path.join(codexDir, 'auth.json');
      final auth = _generator.buildCodexAuth(provider);
      if (isOfficialCodexOAuthProvider(provider) && auth.isEmpty) {
        if ((await _fs.stat(authPath)).isFile) {
          // Preserve OAuth credentials from `codex login` / import.
        } else {
          await _generator.writeJsonAtomic(authPath, auth, fs: _fs);
        }
      } else {
        await _generator.writeJsonAtomic(authPath, auth, fs: _fs);
      }
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
    CliTool cli,
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
