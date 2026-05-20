import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../models/app_provider_config.dart';
import '../repositories/app_provider_repository.dart';
import '../repositories/llm_config_repository.dart';
import 'llm_config_path_resolver.dart';

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
    String? appDataBasePath,
    String? homeDirectory,
    String? currentDirectory,
    String? flashskyaiExecutablePath,
  }) : _repository =
           repository ?? AppProviderRepository(basePath: appDataBasePath),
       _homeDirectory = homeDirectory,
       _currentDirectory = currentDirectory ?? Directory.current.path,
       _flashskyaiExecutablePath = flashskyaiExecutablePath;

  final AppProviderRepository _repository;
  final String? _homeDirectory;
  final String _currentDirectory;
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
    final resolved = resolveLlmConfigPath(
      userOverride: null,
      currentDirectory: _currentDirectory,
      homeDirectory: _homeDirectory,
      cliExecutablePath: _flashskyaiExecutablePath,
    );
    if (resolved.path.isEmpty) return const _ImportedProviders();

    final file = File(resolved.path);
    if (!await file.exists()) return const _ImportedProviders();

    final llm = await LlmConfigRepository(file).load();
    if (llm.providers.isEmpty) return const _ImportedProviders();

    final now = _now();
    final providers = <AppProviderConfig>[];
    for (final entry in llm.providers.entries) {
      final id = sanitizeProviderId(entry.key);
      if (id.isEmpty) continue;
      final legacy = entry.value;
      final defaultModel = llm.models.values
          .where((m) => m.provider == entry.key && m.enabled)
          .map((m) => m.model)
          .firstWhere((m) => m.trim().isNotEmpty, orElse: () => '');
      providers.add(
        AppProviderConfig(
          id: id,
          cli: AppProviderCli.flashskyai,
          name: legacy.name.isNotEmpty ? legacy.name : id,
          category: legacy.type == 'account'
              ? AppProviderCategory.official
              : AppProviderCategory.thirdParty,
          apiKey: legacy.apiKey,
          apiKeyField: 'api_key',
          baseUrl: legacy.baseUrl,
          defaultModel: defaultModel,
          config: {
            'type': legacy.type.isNotEmpty ? legacy.type : 'api',
            'provider_type': legacy.providerType.isNotEmpty
                ? legacy.providerType
                : 'openai',
            if (legacy.proxy) 'proxy': true,
            if (legacy.proxyUrl.isNotEmpty) 'proxy_url': legacy.proxyUrl,
            if (legacy.accounts.isNotEmpty) 'account': legacy.accounts,
            ...legacy.unknownFields,
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

  Future<_ImportedProviders> _importClaude() async {
    final byId = <String, AppProviderConfig>{};
    final sources = <String>{};
    for (final provider in await _importClaudeLive()) {
      byId[provider.id] = provider;
      sources.add('live');
    }
    for (final provider in _importCcSwitch(AppProviderCli.claude)) {
      byId[provider.id] = provider;
      sources.add('cc-switch');
    }
    return _ImportedProviders(byId.values.toList(), sources.toList());
  }

  Future<_ImportedProviders> _importCodex() async {
    final byId = <String, AppProviderConfig>{};
    final sources = <String>{};
    for (final provider in await _importCodexLive()) {
      byId[provider.id] = provider;
      sources.add('live');
    }
    for (final provider in _importCcSwitch(AppProviderCli.codex)) {
      byId[provider.id] = provider;
      sources.add('cc-switch');
    }
    return _ImportedProviders(byId.values.toList(), sources.toList());
  }

  Future<List<AppProviderConfig>> _importClaudeLive() async {
    final home = _homeDirectory?.trim();
    if (home == null || home.isEmpty) return const [];
    final dir = Directory(p.join(home, '.claude'));
    if (!await dir.exists()) return const [];

    final files = <_NamedFile>[];
    final settings = File(p.join(dir.path, 'settings.json'));
    final legacy = File(p.join(dir.path, 'claude.json'));
    if (await settings.exists()) {
      files.add(_NamedFile('default', settings));
    } else if (await legacy.exists()) {
      files.add(_NamedFile('default', legacy));
    }
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith('settings-') || !name.endsWith('.json')) continue;
      final base = name.substring('settings-'.length, name.length - '.json'.length);
      files.add(_NamedFile(sanitizeProviderId(base), entity));
    }

    final now = _now();
    final providers = <AppProviderConfig>[];
    for (final named in files) {
      final config = await _readJsonObject(named.file);
      if (config == null || named.id.isEmpty) continue;
      providers.add(_claudeProviderFromConfig(named.id, config, now));
    }
    return providers;
  }

  Future<List<AppProviderConfig>> _importCodexLive() async {
    final home = _homeDirectory?.trim();
    if (home == null || home.isEmpty) return const [];
    final dir = Directory(p.join(home, '.codex'));
    if (!await dir.exists()) return const [];

    final ids = <String>{};
    if (await File(p.join(dir.path, 'auth.json')).exists() ||
        await File(p.join(dir.path, 'config.toml')).exists()) {
      ids.add('default');
    }
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith('auth-') || !name.endsWith('.json')) continue;
      ids.add(sanitizeProviderId(name.substring('auth-'.length, name.length - '.json'.length)));
    }

    final now = _now();
    final providers = <AppProviderConfig>[];
    for (final id in ids) {
      if (id.isEmpty) continue;
      final authFile = File(
        p.join(dir.path, id == 'default' ? 'auth.json' : 'auth-$id.json'),
      );
      final tomlFile = File(
        p.join(dir.path, id == 'default' ? 'config.toml' : 'config-$id.toml'),
      );
      final auth = await _readJsonObject(authFile) ?? <String, Object?>{};
      final toml = await tomlFile.exists() ? await tomlFile.readAsString() : '';
      if (auth.isEmpty && toml.trim().isEmpty) continue;
      providers.add(_codexProviderFromConfig(id, auth, toml, now));
    }
    return providers;
  }

  List<AppProviderConfig> _importCcSwitch(AppProviderCli cli) {
    final home = _homeDirectory?.trim();
    if (home == null || home.isEmpty) return const [];
    final file = File(p.join(home, '.cc-switch', 'cc-switch.db'));
    if (!file.existsSync()) return const [];

    final appType = cli.value;
    final providers = <AppProviderConfig>[];
    Database? db;
    try {
      db = sqlite3.open(file.path, mode: OpenMode.readOnly);
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
    return AppProviderConfig(
      id: id,
      cli: AppProviderCli.claude,
      name: (name?.trim().isNotEmpty ?? false) ? name!.trim() : id,
      websiteUrl: websiteUrl,
      notes: notes,
      category: category,
      apiKey: apiKey,
      apiKeyField: config['api_key_field']?.toString() ?? apiKeyField,
      baseUrl: baseUrl,
      defaultModel: defaultModel,
      icon: icon,
      iconColor: iconColor,
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
    final parsed = _parseCodexToml(toml);
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

  Future<Map<String, Object?>?> _readJsonObject(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
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

  _CodexTomlParts _parseCodexToml(String toml) {
    final model = RegExp(
      r'^\s*model\s*=\s*"([^"]+)"',
      multiLine: true,
    ).firstMatch(toml)?.group(1) ?? '';
    final baseUrl = RegExp(
      r'^\s*base_url\s*=\s*"([^"]+)"',
      multiLine: true,
    ).firstMatch(toml)?.group(1) ?? '';
    return _CodexTomlParts(model: model, baseUrl: baseUrl);
  }

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  static String sanitizeProviderId(String value) {
    final id = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return id;
  }
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
  const _NamedFile(this.id, this.file);

  final String id;
  final File file;
}

class _CodexTomlParts {
  const _CodexTomlParts({required this.model, required this.baseUrl});

  final String model;
  final String baseUrl;
}
