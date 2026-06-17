import 'dart:convert';

import '../../../models/app_provider_config.dart';
import '../../cli/registry/capabilities/provider_catalog_capability.dart';
import '../../io/filesystem.dart';
import '../cc_switch_catalog_import.dart';
import 'claude_official_provider.dart';
import '../codex/codex_cc_switch_import.dart';

/// Scans `~/.claude` settings profiles and CC Switch rows.
abstract final class ClaudeLiveImport {
  ClaudeLiveImport._();

  static Future<ProviderCatalogSnapshot> loadSnapshot(
    ProviderCatalogLoadContext context,
  ) async {
    final byId = <String, AppProviderConfig>{};
    final sources = <String>{};
    final now = context.resolvedNow();

    for (final provider in await _loadLiveProfiles(context.fs, context.homeDirectory, now)) {
      byId[provider.id] = provider;
      sources.add('live');
    }

    const ccSwitch = CcSwitchCatalogImport();
    for (final row in await ccSwitch.loadRows(
      cli: CliTool.claude,
      fs: context.fs,
      homeDirectory: context.homeDirectory,
    )) {
      if (row.id.isEmpty) continue;
      byId[row.id] = providerFromSettings(
        row.id,
        row.settingsConfig,
        now,
        name: row.name,
        category: row.category,
        websiteUrl: row.websiteUrl,
        notes: row.notes,
        icon: row.icon,
        iconColor: row.iconColor,
        createdAt: row.createdAt,
        meta: row.meta,
      );
      sources.add('cc-switch');
    }

    return ProviderCatalogSnapshot(
      providers: byId.values.toList(),
      sources: sources.toList(),
      mirrorToFlashskyai: true,
    );
  }

  static Future<List<AppProviderConfig>> _loadLiveProfiles(
    Filesystem fs,
    String homeDirectory,
    int now,
  ) async {
    final home = homeDirectory.trim();
    if (home.isEmpty) return const [];

    final ctx = fs.pathContext;
    final dirPath = ctx.join(home, '.claude');
    if (!(await fs.stat(dirPath)).isDirectory) return const [];

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
      files.add(_NamedFile(sanitizeImportedProviderId(base), ctx.join(dirPath, name)));
    }

    final providers = <AppProviderConfig>[];
    for (final named in files) {
      final config = await _readJsonObject(fs, named.path);
      if (config == null || named.id.isEmpty) continue;
      providers.add(providerFromSettings(named.id, config, now));
    }
    return providers;
  }

  static AppProviderConfig providerFromSettings(
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
      cli: CliTool.claude,
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
}

Future<Map<String, Object?>?> _readJsonObject(Filesystem fs, String path) async {
  try {
    final content = await fs.readString(path);
    if (content == null || content.isEmpty) return null;
    final decoded = jsonDecode(content);
    if (decoded is! Map) return null;
    return Map<String, Object?>.from(decoded);
  } on Object {
    return null;
  }
}

Map<String, String> _stringMap(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      entry.key.toString(): entry.value?.toString() ?? '',
  };
}

class _NamedFile {
  const _NamedFile(this.id, this.path);

  final String id;
  final String path;
}
