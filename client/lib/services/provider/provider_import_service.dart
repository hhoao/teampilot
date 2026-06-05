import 'dart:convert';
import 'dart:io' show Directory, File;

import 'package:sqlite3/sqlite3.dart';
import '../../models/app_provider_config.dart';
import '../../models/llm_config.dart';
import '../../repositories/app_provider_repository.dart';
import '../storage/app_storage.dart';
import 'claude_official_provider.dart';
import '../io/filesystem.dart';
import 'llm_config_path_resolver.dart';
import 'codex_cc_switch_import.dart';
import 'codex_toml_parser.dart';

class ProviderImportResult {
  const ProviderImportResult({
    required this.cli,
    this.added = 0,
    this.updated = 0,
    this.skipped = 0,
    this.mirroredToFlashskyai = 0,
    this.mirrorSkipped = 0,
    this.sources = const [],
  });

  final AppProviderCli cli;
  final int added;
  final int updated;
  final int skipped;
  final int mirroredToFlashskyai;
  final int mirrorSkipped;
  final List<String> sources;

  bool get changed => added > 0 || updated > 0 || mirroredToFlashskyai > 0;
}

class ProviderImportService {
  ProviderImportService({
    AppProviderRepository? repository,
    String? flashskyaiExecutablePath,
  }) : _repository = repository ?? AppProviderRepository(),
       _flashskyaiExecutablePath = flashskyaiExecutablePath;

  final AppProviderRepository _repository;
  final String? _flashskyaiExecutablePath;

  Future<ProviderImportResult> importForCli(
    AppProviderCli cli, {
    required bool onlyIfEmpty,
  }) async {
    final existing = await _repository.loadProviders(cli);
    if (onlyIfEmpty && existing.isNotEmpty) {
      return ProviderImportResult(cli: cli, skipped: existing.length);
    }

    final imported = switch (cli) {
      AppProviderCli.flashskyai => await _importFlashskyai(),
      AppProviderCli.claude => await _importClaude(),
      AppProviderCli.codex => await _importCodex(),
    };
    if (imported.providers.isEmpty) {
      return ProviderImportResult(cli: cli);
    }

    final currentById = {for (final provider in existing) provider.id: provider};
    var added = 0;
    var updated = 0;
    for (final provider in imported.providers) {
      if (currentById.containsKey(provider.id)) {
        updated++;
      } else {
        added++;
      }
      currentById[provider.id] = provider;
    }
    await _repository.saveProviders(cli, currentById.values.toList());

    var mirrored = 0;
    var mirrorSkipped = 0;
    if (cli == AppProviderCli.claude || cli == AppProviderCli.codex) {
      final mirror = await _mirrorToFlashskyai(imported.providers);
      mirrored = mirror.added;
      mirrorSkipped = mirror.skipped;
    }

    return ProviderImportResult(
      cli: cli,
      added: added,
      updated: updated,
      mirroredToFlashskyai: mirrored,
      mirrorSkipped: mirrorSkipped,
      sources: imported.sources,
    );
  }

  Future<_ImportedProviders> _importFlashskyai() async {
    final fs = AppStorage.fs;
    final resolved = resolveLlmConfigPath(
      userOverride: null,
      currentDirectory: AppStorage.cwd,
      homeDirectory: AppStorage.home,
      cliExecutablePath: _flashskyaiExecutablePath,
      usePosixPaths: AppStorage.usesPosixPaths,
    );
    if (resolved.path.isEmpty) return const _ImportedProviders();

    final llm = await _loadLlmConfig(fs, resolved.path);
    if (llm.providers.isEmpty) return const _ImportedProviders();

    final now = _now();
    final providers = <AppProviderConfig>[];
    for (final entry in llm.providers.entries) {
      final id = sanitizeProviderId(entry.key);
      if (id.isEmpty) continue;
      final source = entry.value;
      final defaultModel = llm.models.values
          .where((m) => m.provider == entry.key && m.enabled)
          .map((m) => m.model)
          .firstWhere((m) => m.trim().isNotEmpty, orElse: () => '');
      providers.add(
        AppProviderConfig(
          id: id,
          cli: AppProviderCli.flashskyai,
          name: source.name.isNotEmpty ? source.name : id,
          category: source.type == 'account'
              ? AppProviderCategory.official
              : AppProviderCategory.thirdParty,
          apiKey: source.apiKey,
          apiKeyField: 'api_key',
          baseUrl: source.baseUrl,
          defaultModel: defaultModel,
          config: {
            'type': source.type.isNotEmpty ? source.type : 'api',
            'provider_type': source.providerType.isNotEmpty
                ? source.providerType
                : 'openai',
            if (source.proxy) 'proxy': true,
            if (source.proxyUrl.isNotEmpty) 'proxy_url': source.proxyUrl,
            if (source.accounts.isNotEmpty) 'account': source.accounts,
            ...source.unknownFields,
            if (llm.models.isNotEmpty)
              'models': {
                for (final model in llm.models.entries)
                  if (model.value.provider == entry.key)
                    model.key: {
                      ...model.value.toJson(),
                      'provider': id,
                    },
              },
          },
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    return _ImportedProviders(providers, const ['llm_config']);
  }

  Future<LlmConfig> _loadLlmConfig(Filesystem fs, String path) async {
    final content = await fs.readString(path);
    if (content == null || content.isEmpty) {
      return const LlmConfig();
    }
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        return const LlmConfig();
      }
      return LlmConfig.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return const LlmConfig();
    } on TypeError {
      return const LlmConfig();
    }
  }

  Future<_ImportedProviders> _importClaude() async {
    final byId = <String, AppProviderConfig>{};
    final sources = <String>{};
    for (final provider in await _importClaudeLive()) {
      byId[provider.id] = provider;
      sources.add('live');
    }
    for (final provider in await _importCcSwitch(AppProviderCli.claude)) {
      byId[provider.id] = provider;
      sources.add('cc-switch');
    }
    return _ImportedProviders(byId.values.toList(), sources.toList());
  }

  Future<_ImportedProviders> _importCodex() async {
    const importer = CodexCcSwitchImport();
    final runtime = await importer.loadRuntime();
    final byId = <String, AppProviderConfig>{};
    final sources = <String>{};
    final now = _now();

    if (runtime.hasLive) {
      byId['default'] = importer.buildLiveDefaultProvider(runtime, now);
      sources.add('live');
    }
    for (final provider in await _importCodexLiveExtraProfiles()) {
      byId[provider.id] = provider;
      sources.add('live');
    }
    for (final row in await importer.loadCatalog()) {
      byId[row.id] = importer.buildCatalogProvider(
        row: row,
        runtime: runtime,
        now: now,
      );
      sources.add('cc-switch');
    }
    return _ImportedProviders(byId.values.toList(), sources.toList());
  }

  Future<List<AppProviderConfig>> _importClaudeLive() async {
    final fs = AppStorage.fs;
    final ctx = fs.pathContext;
    final home = AppStorage.home.trim();
    if (home.isEmpty) return const [];

    final dirPath = ctx.join(home, '.claude');
    final dirStat = await fs.stat(dirPath);
    if (!dirStat.isDirectory) return const [];

    final files = <_NamedFile>[];
    final settingsPath = ctx.join(dirPath, 'settings.json');
    if ((await fs.stat(settingsPath)).isFile) {
      files.add(_NamedFile('default', settingsPath));
    }
    for (final entry in await fs.listDir(dirPath)) {
      if (entry.isDirectory) continue;
      final name = entry.name;
      if (!name.startsWith('settings-') || !name.endsWith('.json')) continue;
      final base = name.substring('settings-'.length, name.length - '.json'.length);
      files.add(_NamedFile(sanitizeProviderId(base), ctx.join(dirPath, name)));
    }

    final now = _now();
    final providers = <AppProviderConfig>[];
    for (final named in files) {
      final config = await _readJsonObject(named.path);
      if (config == null || named.id.isEmpty) continue;
      providers.add(_claudeProviderFromConfig(named.id, config, now));
    }
    return providers;
  }

  Future<List<AppProviderConfig>> _importCodexLiveExtraProfiles() async {
    final fs = AppStorage.fs;
    final ctx = fs.pathContext;
    final home = AppStorage.home.trim();
    if (home.isEmpty) return const [];

    final dirPath = ctx.join(home, '.codex');
    final dirStat = await fs.stat(dirPath);
    if (!dirStat.isDirectory) return const [];

    final ids = <String>{};
    for (final entry in await fs.listDir(dirPath)) {
      if (entry.isDirectory) continue;
      final name = entry.name;
      if (!name.startsWith('auth-') || !name.endsWith('.json')) continue;
      ids.add(
        sanitizeProviderId(
          name.substring('auth-'.length, name.length - '.json'.length),
        ),
      );
    }

    final now = _now();
    final providers = <AppProviderConfig>[];
    for (final id in ids) {
      if (id.isEmpty) continue;
      final authPath = ctx.join(
        dirPath,
        id == 'default' ? 'auth.json' : 'auth-$id.json',
      );
      final tomlPath = ctx.join(
        dirPath,
        id == 'default' ? 'config.toml' : 'config-$id.toml',
      );
      final auth = await _readJsonObject(authPath) ?? <String, Object?>{};
      final toml = await fs.readString(tomlPath) ?? '';
      if (auth.isEmpty && toml.trim().isEmpty) continue;
      providers.add(_codexProviderFromConfig(id, auth, toml, now));
    }
    return providers;
  }

  Future<List<AppProviderConfig>> _importCcSwitch(AppProviderCli cli) async {
    final fs = AppStorage.fs;
    final ctx = fs.pathContext;
    final home = AppStorage.home.trim();
    if (home.isEmpty) return const [];

    final dbPath = ctx.join(home, '.cc-switch', 'cc-switch.db');
    final bytes = await fs.readBytes(dbPath);
    if (bytes == null || bytes.isEmpty) return const [];

    final appType = cli.value;
    final providers = <AppProviderConfig>[];
    Database? db;
    final tempDir = await Directory.systemTemp.createTemp('cc-switch-');
    try {
      final tempFile = File(ctx.join(tempDir.path, 'cc-switch.db'));
      await tempFile.writeAsBytes(bytes);
      db = sqlite3.open(tempFile.path, mode: OpenMode.readOnly);
      final rows = db.select(
        '''
SELECT id, name, settings_config, website_url, category, created_at,
       notes, icon, icon_color, meta
FROM providers
WHERE app_type = ?
''',
        [appType],
      );
      for (final row in rows) {
        final id = sanitizeProviderId(row['id']?.toString() ?? '');
        if (id.isEmpty) continue;
        final settings = _jsonStringToMap(row['settings_config']);
        if (settings == null) continue;
        final now = _now();
        if (cli == AppProviderCli.claude) {
          providers.add(
            _claudeProviderFromConfig(
              id,
              settings,
              now,
              name: row['name']?.toString(),
              category: AppProviderCategory.fromJson(row['category']),
              websiteUrl: row['website_url']?.toString() ?? '',
              notes: row['notes']?.toString() ?? '',
              icon: row['icon']?.toString() ?? '',
              iconColor: row['icon_color']?.toString() ?? '',
              createdAt: (row['created_at'] as int?) ?? 0,
              meta: _jsonStringToMap(row['meta']),
            ),
          );
        } else if (cli == AppProviderCli.codex) {
          final auth = _mapFrom(settings['auth']);
          final toml =
              settings['configToml']?.toString() ??
              settings['config_toml']?.toString() ??
              settings['config']?.toString() ??
              '';
          providers.add(
            _codexProviderFromConfig(
              id,
              auth ?? const {},
              toml,
              now,
              name: row['name']?.toString(),
              category: AppProviderCategory.fromJson(row['category']),
              websiteUrl: row['website_url']?.toString() ?? '',
              notes: row['notes']?.toString() ?? '',
              icon: row['icon']?.toString() ?? '',
              iconColor: row['icon_color']?.toString() ?? '',
              createdAt: (row['created_at'] as int?) ?? 0,
              meta: _jsonStringToMap(row['meta']),
            ),
          );
        }
      }
    } on Object {
      return const [];
    } finally {
      db?.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
    return providers;
  }

  AppProviderConfig _claudeProviderFromConfig(
    String id,
    Map<String, Object?> config,
    int now, {
    String? name,
    AppProviderCategory category = AppProviderCategory.custom,
    String websiteUrl = '',
    String notes = '',
    String icon = '',
    String iconColor = '',
    int createdAt = 0,
    Map<String, Object?>? meta,
  }) {
    final env = _stringMap(config['env']);
    final apiKey =
        env['ANTHROPIC_AUTH_TOKEN'] ?? env['ANTHROPIC_API_KEY'] ?? '';
    final apiKeyField = env.containsKey('ANTHROPIC_AUTH_TOKEN')
        ? 'ANTHROPIC_AUTH_TOKEN'
        : 'ANTHROPIC_API_KEY';
    final baseUrl = env['ANTHROPIC_BASE_URL'] ?? '';
    final defaultModel =
        env['ANTHROPIC_MODEL'] ??
        env['ANTHROPIC_DEFAULT_SONNET_MODEL'] ??
        env['ANTHROPIC_DEFAULT_OPUS_MODEL'] ??
        env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] ??
        '';
    final resolvedCategory =
        category == AppProviderCategory.custom &&
            isOfficialClaudeSettings(config)
        ? AppProviderCategory.official
        : category;
    return AppProviderConfig(
      id: id,
      cli: AppProviderCli.claude,
      name: (name?.trim().isNotEmpty ?? false) ? name!.trim() : id,
      websiteUrl: websiteUrl,
      notes: notes,
      category: resolvedCategory,
      apiKey: apiKey,
      apiKeyField: config['api_key_field']?.toString() ?? apiKeyField,
      baseUrl: baseUrl,
      defaultModel: defaultModel,
      icon: icon,
      iconColor: iconColor,
      isOfficial: resolvedCategory == AppProviderCategory.official,
      config: {
        ...config,
        if (meta != null && meta.isNotEmpty) 'meta': meta,
      },
      createdAt: createdAt > 0 ? createdAt : now,
      updatedAt: now,
    );
  }

  AppProviderConfig _codexProviderFromConfig(
    String id,
    Map<String, Object?> auth,
    String toml,
    int now, {
    String? name,
    AppProviderCategory category = AppProviderCategory.custom,
    String websiteUrl = '',
    String notes = '',
    String icon = '',
    String iconColor = '',
    int createdAt = 0,
    Map<String, Object?>? meta,
  }) {
    final parsed = CodexTomlParser.parse(toml);
    final apiKey =
        auth['OPENAI_API_KEY']?.toString() ??
        auth['openai_api_key']?.toString() ??
        auth['api_key']?.toString() ??
        '';
    return AppProviderConfig(
      id: id,
      cli: AppProviderCli.codex,
      name: (name?.trim().isNotEmpty ?? false) ? name!.trim() : id,
      websiteUrl: websiteUrl,
      notes: notes,
      category: category,
      apiKey: apiKey,
      apiKeyField: 'OPENAI_API_KEY',
      baseUrl: parsed.baseUrl,
      defaultModel: parsed.model,
      icon: icon,
      iconColor: iconColor,
      config: {
        'auth': auth,
        if (toml.trim().isNotEmpty) 'configToml': toml,
        if (meta != null && meta.isNotEmpty) 'meta': meta,
      },
      createdAt: createdAt > 0 ? createdAt : now,
      updatedAt: now,
    );
  }

  Future<_MirrorResult> _mirrorToFlashskyai(
    List<AppProviderConfig> providers,
  ) async {
    final existing = await _repository.loadProviders(AppProviderCli.flashskyai);
    final byId = {for (final provider in existing) provider.id: provider};
    final existingModelIds = <String>{
      for (final provider in existing) ..._flashskyaiModelIds(provider),
    };
    var added = 0;
    var skipped = 0;
    for (final provider in providers) {
      final mirrored = _toFlashskyaiProvider(
        provider,
        reservedModelIds: existingModelIds,
      );
      if (mirrored == null) continue;
      if (byId.containsKey(mirrored.id)) {
        skipped++;
        continue;
      }
      existingModelIds.addAll(_flashskyaiModelIds(mirrored));
      byId[mirrored.id] = mirrored;
      added++;
    }
    if (added > 0) {
      await _repository.saveProviders(
        AppProviderCli.flashskyai,
        byId.values.toList(),
      );
    }
    return _MirrorResult(added: added, skipped: skipped);
  }

  AppProviderConfig? _toFlashskyaiProvider(
    AppProviderConfig provider, {
    Set<String> reservedModelIds = const {},
  }) {
    if (provider.cli == AppProviderCli.flashskyai) return null;
    if (provider.id == 'default' &&
        provider.apiKey.trim().isEmpty &&
        provider.baseUrl.trim().isEmpty) {
      return null;
    }
    final now = _now();
    final model = provider.defaultModel.trim();
    final shouldMirrorModel =
        model.isNotEmpty && !reservedModelIds.contains(model);
    final mirroredDefaultModel = shouldMirrorModel ? model : '';
    final providerType = _providerTypeFor(provider);
    return AppProviderConfig(
      id: provider.id,
      cli: AppProviderCli.flashskyai,
      name: provider.name,
      notes: provider.notes,
      websiteUrl: provider.websiteUrl,
      apiKeyUrl: provider.apiKeyUrl,
      category: provider.category,
      apiKey: provider.apiKey,
      apiKeyField: 'api_key',
      baseUrl: provider.baseUrl,
      defaultModel: mirroredDefaultModel,
      icon: provider.icon,
      iconColor: provider.iconColor,
      isOfficial: provider.isOfficial,
      isPartner: provider.isPartner,
      partnerPromotionKey: provider.partnerPromotionKey,
      endpointCandidates: provider.endpointCandidates,
      config: {
        'type': 'api',
        'provider_type': providerType,
        if (shouldMirrorModel)
          'models': {
            model: {
              'name': model,
              'provider': provider.id,
              'model': model,
              'enabled': true,
            },
          },
      },
      createdAt: now,
      updatedAt: now,
    );
  }

  Set<String> _flashskyaiModelIds(AppProviderConfig provider) {
    final rawModels = provider.config['models'];
    if (rawModels is Map) {
      return rawModels.keys.map((key) => key.toString()).toSet();
    }
    final model = provider.defaultModel.trim();
    if (model.isEmpty) return const {};
    return {model};
  }

  String _providerTypeFor(AppProviderConfig provider) {
    if (provider.cli == AppProviderCli.codex) return 'openai';
    final url = provider.baseUrl.toLowerCase();
    if (url.contains('anthropic') || url.contains('claude')) {
      return 'anthropic';
    }
    return 'openai';
  }

  Future<Map<String, Object?>?> _readJsonObject(String path) async {
    try {
      final content = await AppStorage.fs.readString(path);
      if (content == null || content.isEmpty) return null;
      final decoded = jsonDecode(content);
      if (decoded is! Map) return null;
      return Map<String, Object?>.from(decoded);
    } on Object {
      return null;
    }
  }

  Map<String, Object?>? _jsonStringToMap(Object? raw) {
    if (raw is Map) return Map<String, Object?>.from(raw);
    final text = raw?.toString() ?? '';
    if (text.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return Map<String, Object?>.from(decoded);
    } on Object {
      return null;
    }
  }

  Map<String, Object?>? _mapFrom(Object? raw) {
    if (raw is Map) return Map<String, Object?>.from(raw);
    return null;
  }

  Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        entry.key.toString(): entry.value?.toString() ?? '',
    };
  }

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  static String sanitizeProviderId(String value) =>
      sanitizeImportedProviderId(value);
}

class _ImportedProviders {
  const _ImportedProviders([
    this.providers = const [],
    this.sources = const [],
  ]);

  final List<AppProviderConfig> providers;
  final List<String> sources;
}

class _MirrorResult {
  const _MirrorResult({required this.added, required this.skipped});

  final int added;
  final int skipped;
}

class _NamedFile {
  const _NamedFile(this.id, this.path);

  final String id;
  final String path;
}

