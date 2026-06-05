import 'dart:convert';
import 'dart:io' show Directory, File;

import 'package:sqlite3/sqlite3.dart';

import '../../models/app_provider_config.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import 'codex_toml_parser.dart';

/// Live `~/.codex` files plus resolved CC Switch current provider id.
class CodexRuntimeSnapshot {
  const CodexRuntimeSnapshot({
    this.liveToml = '',
    this.liveAuth = const {},
    this.proxyTakeover = false,
    this.currentProviderId = '',
  });

  final String liveToml;
  final Map<String, Object?> liveAuth;
  final bool proxyTakeover;
  final String currentProviderId;

  bool get hasLive =>
      liveToml.trim().isNotEmpty || liveAuth.isNotEmpty;
}

/// One Codex row from `~/.cc-switch/cc-switch.db`.
class CcSwitchCodexCatalogRow {
  const CcSwitchCodexCatalogRow({
    required this.id,
    required this.name,
    required this.catalogToml,
    required this.catalogAuth,
    this.websiteUrl = '',
    this.category = AppProviderCategory.custom,
    this.notes = '',
    this.icon = '',
    this.iconColor = '',
    this.createdAt = 0,
    this.meta = const {},
  });

  final String id;
  final String name;
  final String catalogToml;
  final Map<String, Object?> catalogAuth;
  final String websiteUrl;
  final AppProviderCategory category;
  final String notes;
  final String icon;
  final String iconColor;
  final int createdAt;
  final Map<String, Object?> meta;
}

/// Reads live Codex config and CC Switch catalog for import.
class CodexCcSwitchImport {
  const CodexCcSwitchImport();

  Future<CodexRuntimeSnapshot> loadRuntime({Filesystem? fs, String? home}) async {
    final store = fs ?? AppStorage.fs;
    final ctx = store.pathContext;
    final homeDir = (home ?? AppStorage.home).trim();
    if (homeDir.isEmpty) {
      return const CodexRuntimeSnapshot();
    }

    final dirPath = ctx.join(homeDir, '.codex');
    final dirStat = await store.stat(dirPath);
    if (!dirStat.isDirectory) {
      return const CodexRuntimeSnapshot();
    }

    final authPath = ctx.join(dirPath, 'auth.json');
    final tomlPath = ctx.join(dirPath, 'config.toml');
    final liveAuth = await _readJsonObject(store, authPath) ?? const {};
    final liveToml = await store.readString(tomlPath) ?? '';
    final takeover = CodexTomlParser.detectProxyTakeover(
      liveToml: liveToml,
      liveAuth: liveAuth,
    );

    final currentFromSettings = await _readCurrentCodexProviderId(
      store,
      homeDir,
    );
    final currentFromDb = currentFromSettings.isNotEmpty
        ? currentFromSettings
        : await _readCurrentCodexProviderIdFromDb(store, homeDir);

    return CodexRuntimeSnapshot(
      liveToml: liveToml,
      liveAuth: liveAuth,
      proxyTakeover: takeover,
      currentProviderId: sanitizeImportedProviderId(currentFromDb),
    );
  }

  Future<List<CcSwitchCodexCatalogRow>> loadCatalog({
    Filesystem? fs,
    String? home,
  }) async {
    final store = fs ?? AppStorage.fs;
    final ctx = store.pathContext;
    final homeDir = (home ?? AppStorage.home).trim();
    if (homeDir.isEmpty) return const [];

    final dbPath = ctx.join(homeDir, '.cc-switch', 'cc-switch.db');
    final bytes = await store.readBytes(dbPath);
    if (bytes == null || bytes.isEmpty) return const [];

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
        ['codex'],
      );
      final catalog = <CcSwitchCodexCatalogRow>[];
      for (final row in rows) {
        final id = sanitizeImportedProviderId(row['id']?.toString() ?? '');
        if (id.isEmpty) continue;
        final settings = _jsonStringToMap(row['settings_config']);
        if (settings == null) continue;
        final catalogToml = _catalogTomlFromSettings(settings);
        final catalogAuth = _mapFrom(settings['auth']) ?? const {};
        catalog.add(
          CcSwitchCodexCatalogRow(
            id: id,
            name: row['name']?.toString() ?? id,
            catalogToml: catalogToml,
            catalogAuth: catalogAuth,
            websiteUrl: row['website_url']?.toString() ?? '',
            category: AppProviderCategory.fromJson(row['category']),
            notes: row['notes']?.toString() ?? '',
            icon: row['icon']?.toString() ?? '',
            iconColor: row['icon_color']?.toString() ?? '',
            createdAt: (row['created_at'] as int?) ?? 0,
            meta: _jsonStringToMap(row['meta']) ?? const {},
          ),
        );
      }
      return catalog;
    } on Object {
      return const [];
    } finally {
      db?.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  AppProviderConfig buildLiveDefaultProvider(
    CodexRuntimeSnapshot runtime,
    int now,
  ) {
    return _buildCodexProvider(
      id: 'default',
      auth: runtime.liveAuth,
      effectiveToml: runtime.liveToml,
      upstreamToml: '',
      now: now,
      meta: {
        'importSources': ['live'],
        if (runtime.proxyTakeover) 'proxyTakeover': true,
      },
    );
  }

  AppProviderConfig buildCatalogProvider({
    required CcSwitchCodexCatalogRow row,
    required CodexRuntimeSnapshot runtime,
    required int now,
  }) {
    final isCurrent =
        row.id.isNotEmpty &&
        runtime.currentProviderId.isNotEmpty &&
        row.id == runtime.currentProviderId;
    final effectiveToml = isCurrent && runtime.liveToml.trim().isNotEmpty
        ? runtime.liveToml
        : row.catalogToml;
    final upstreamToml =
        isCurrent && row.catalogToml.trim().isNotEmpty ? row.catalogToml : '';
    final auth = isCurrent
        ? _mergeCodexAuth(
            catalogAuth: row.catalogAuth,
            liveAuth: runtime.liveAuth,
            proxyTakeover: runtime.proxyTakeover,
          )
        : row.catalogAuth;

    final importSources = <String>['cc-switch'];
    if (isCurrent && runtime.hasLive) importSources.add('live');

    final meta = <String, Object?>{
      ...row.meta,
      'ccSwitchProviderId': row.id,
      'importSources': importSources,
      if (isCurrent && runtime.proxyTakeover) 'proxyTakeover': true,
    };

    return _buildCodexProvider(
      id: row.id,
      name: row.name,
      websiteUrl: row.websiteUrl,
      notes: row.notes,
      category: row.category,
      icon: row.icon,
      iconColor: row.iconColor,
      createdAt: row.createdAt,
      auth: auth,
      effectiveToml: effectiveToml,
      upstreamToml: upstreamToml,
      now: now,
      meta: meta,
    );
  }

  AppProviderConfig _buildCodexProvider({
    required String id,
    required Map<String, Object?> auth,
    required String effectiveToml,
    required String upstreamToml,
    required int now,
    String? name,
    AppProviderCategory category = AppProviderCategory.custom,
    String websiteUrl = '',
    String notes = '',
    String icon = '',
    String iconColor = '',
    int createdAt = 0,
    Map<String, Object?> meta = const {},
  }) {
    final parsed = CodexTomlParser.parse(effectiveToml);
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
        if (effectiveToml.trim().isNotEmpty) 'configToml': effectiveToml,
        if (upstreamToml.trim().isNotEmpty) 'upstreamConfigToml': upstreamToml,
        if (meta.isNotEmpty) 'meta': meta,
      },
      createdAt: createdAt > 0 ? createdAt : now,
      updatedAt: now,
    );
  }

  Map<String, Object?> _mergeCodexAuth({
    required Map<String, Object?> catalogAuth,
    required Map<String, Object?> liveAuth,
    required bool proxyTakeover,
  }) {
    if (!proxyTakeover) {
      if (liveAuth.isNotEmpty) return Map<String, Object?>.from(liveAuth);
      return Map<String, Object?>.from(catalogAuth);
    }
    final merged = Map<String, Object?>.from(
      catalogAuth.isNotEmpty ? catalogAuth : liveAuth,
    );
    final liveKey = liveAuth['OPENAI_API_KEY']?.toString() ?? '';
    if (liveKey == CodexTomlParser.proxyManagedToken || liveKey.isEmpty) {
      for (final entry in catalogAuth.entries) {
        final value = entry.value?.toString() ?? '';
        if (value.isNotEmpty && value != CodexTomlParser.proxyManagedToken) {
          merged[entry.key] = entry.value;
        }
      }
    } else {
      merged.addAll(liveAuth);
    }
    return merged;
  }

  Future<String> _readCurrentCodexProviderId(
    Filesystem store,
    String homeDir,
  ) async {
    final path = store.pathContext.join(homeDir, '.cc-switch', 'config.json');
    final config = await _readJsonObject(store, path);
    if (config == null) return '';
    final raw = config['current_provider_codex']?.toString() ?? '';
    return raw.trim();
  }

  Future<String> _readCurrentCodexProviderIdFromDb(
    Filesystem store,
    String homeDir,
  ) async {
    final ctx = store.pathContext;
    final dbPath = ctx.join(homeDir, '.cc-switch', 'cc-switch.db');
    final bytes = await store.readBytes(dbPath);
    if (bytes == null || bytes.isEmpty) return '';

    Database? db;
    final tempDir = await Directory.systemTemp.createTemp('cc-switch-current-');
    try {
      final tempFile = File(ctx.join(tempDir.path, 'cc-switch.db'));
      await tempFile.writeAsBytes(bytes);
      db = sqlite3.open(tempFile.path, mode: OpenMode.readOnly);
      final rows = db.select(
        "SELECT id FROM providers WHERE app_type = 'codex' AND is_current = 1 LIMIT 1",
      );
      if (rows.isEmpty) return '';
      return rows.first['id']?.toString() ?? '';
    } on Object {
      return '';
    } finally {
      db?.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  String _catalogTomlFromSettings(Map<String, Object?> settings) {
    return settings['configToml']?.toString() ??
        settings['config_toml']?.toString() ??
        settings['config']?.toString() ??
        '';
  }

  Future<Map<String, Object?>?> _readJsonObject(
    Filesystem store,
    String path,
  ) async {
    try {
      final content = await store.readString(path);
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
}

String sanitizeImportedProviderId(String value) {
  final id = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return id;
}
