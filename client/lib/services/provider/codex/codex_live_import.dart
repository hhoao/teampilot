import 'dart:convert';

import '../../../models/app_provider_config.dart';
import '../../cli/registry/capabilities/provider_catalog_capability.dart';
import '../../io/filesystem.dart';
import 'codex_cc_switch_import.dart';
import 'codex_toml_parser.dart';

/// Scans `~/.codex` live profiles and CC Switch rows.
abstract final class CodexLiveImport {
  CodexLiveImport._();

  static Future<ProviderCatalogSnapshot> loadSnapshot(
    ProviderCatalogLoadContext context,
  ) async {
    const importer = CodexCcSwitchImport();
    final runtime = await importer.loadRuntime(
      fs: context.fs,
      home: context.homeDirectory,
    );
    final byId = <String, AppProviderConfig>{};
    final sources = <String>{};
    final now = context.resolvedNow();

    if (runtime.hasLive) {
      byId['default'] = importer.buildLiveDefaultProvider(runtime, now);
      sources.add('live');
    }
    for (final provider in await _loadExtraProfiles(context, now)) {
      byId[provider.id] = provider;
      sources.add('live');
    }
    for (final row in await importer.loadCatalog(
      fs: context.fs,
      home: context.homeDirectory,
    )) {
      byId[row.id] = importer.buildCatalogProvider(
        row: row,
        runtime: runtime,
        now: now,
      );
      sources.add('cc-switch');
    }

    return ProviderCatalogSnapshot(
      providers: byId.values.toList(),
      sources: sources.toList(),
      mirrorToFlashskyai: true,
    );
  }

  static Future<List<AppProviderConfig>> _loadExtraProfiles(
    ProviderCatalogLoadContext context,
    int now,
  ) async {
    final fs = context.fs;
    final ctx = fs.pathContext;
    final home = context.homeDirectory.trim();
    if (home.isEmpty) return const [];

    final dirPath = ctx.join(home, '.codex');
    if (!(await fs.stat(dirPath)).isDirectory) return const [];

    final ids = <String>{};
    for (final entry in await fs.listDir(dirPath)) {
      if (entry.isDirectory) continue;
      final name = entry.name;
      if (!name.startsWith('auth-') || !name.endsWith('.json')) continue;
      ids.add(
        sanitizeImportedProviderId(
          name.substring('auth-'.length, name.length - '.json'.length),
        ),
      );
    }

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
      final auth = await _readJsonObject(fs, authPath) ?? <String, Object?>{};
      final toml = await fs.readString(tomlPath) ?? '';
      if (auth.isEmpty && toml.trim().isEmpty) continue;
      providers.add(providerFromConfig(id, auth, toml, now));
    }
    return providers;
  }

  static AppProviderConfig providerFromConfig(
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
      cli: CliTool.codex,
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
