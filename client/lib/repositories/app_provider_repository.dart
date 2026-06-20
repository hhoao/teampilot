import 'dart:convert';

import '../models/app_provider_config.dart';
import '../services/storage/app_storage.dart';
import '../services/provider/claude/claude_provider_credentials_service.dart';
import '../services/provider/codex/codex_provider_credentials_service.dart';
import '../services/provider/cursor/cursor_provider_credentials_service.dart';
import '../services/provider/opencode/opencode_provider_credentials_service.dart';
import '../services/io/filesystem.dart';
import '../services/provider/tool_config_generator.dart';
import 'provider_persistence/claude_provider_persistence.dart';
import 'provider_persistence/codex_provider_persistence.dart';
import 'provider_persistence/cursor_provider_persistence.dart';
import 'provider_persistence/flashskyai_provider_persistence.dart';
import 'provider_persistence/opencode_provider_persistence.dart';
import 'provider_persistence/provider_persistence_strategy.dart';

export 'provider_persistence/provider_persistence_strategy.dart'
    show AppProviderRepositoryException;

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

  /// Per-CLI persistence strategies (credential probing + native config),
  /// wired with this repository's collaborators. Replaces the former per-CLI
  /// `switch` blocks; each CLI's logic lives in its own strategy file.
  late final Map<CliTool, ProviderPersistenceStrategy> _strategies = {
    CliTool.claude: ClaudeProviderPersistence(credentials: _claudeCredentials),
    CliTool.cursor: CursorProviderPersistence(credentials: _cursorCredentials),
    CliTool.codex: CodexProviderPersistence(credentials: _codexCredentials),
    CliTool.opencode: OpencodeProviderPersistence(
      credentials: _opencodeCredentials,
    ),
    CliTool.flashskyai: const FlashskyaiProviderPersistence(),
  };

  ProviderPersistenceContext get _persistenceContext =>
      ProviderPersistenceContext(
        fs: _fs,
        basePath: _basePath,
        generator: _generator,
        resolveHome: () => AppStorage.home.trim(),
        save: saveProviders,
      );

  Future<List<AppProviderConfig>> loadProviders(
    CliTool cli, {
    bool importCredentialsFromGlobal = false,
  }) async {
    var providers = await _loadProvidersFromDisk(cli);
    final strategy = _strategies[cli];
    if (strategy == null) return providers;
    if (importCredentialsFromGlobal && strategy is CredentialProbeSupport) {
      providers = await strategy.importOfficialCredentialsFromGlobal(
        _persistenceContext,
        providers,
      );
    }
    return strategy.reconcileLoaded(_persistenceContext, providers);
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

    await _strategies[cli]?.reconcileSaved(_persistenceContext, merged);
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
