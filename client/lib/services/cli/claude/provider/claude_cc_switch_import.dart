import 'dart:convert';
import 'dart:io' show Directory, File;

import 'package:sqlite3/sqlite3.dart';

import '../../../../models/app_provider_config.dart';
import '../../../io/filesystem.dart';
import '../../../storage/app_storage.dart';
import '../../codex/provider/codex_cc_switch_import.dart';
import 'claude_live_import.dart';
import 'claude_settings_parser.dart';

/// Live `~/.claude/settings.json` plus resolved CC Switch current provider id.
class ClaudeRuntimeSnapshot {
  const ClaudeRuntimeSnapshot({
    this.liveSettings = const {},
    this.proxyTakeover = false,
    this.currentProviderId = '',
  });

  final Map<String, Object?> liveSettings;
  final bool proxyTakeover;
  final String currentProviderId;

  Map<String, Object?> get liveEnv =>
      ClaudeSettingsParser.envFromSettings(liveSettings);

  bool get hasLive => liveSettings.isNotEmpty;
}

/// One Claude row from `~/.cc-switch/cc-switch.db`.
class CcSwitchClaudeCatalogRow {
  const CcSwitchClaudeCatalogRow({
    required this.id,
    required this.name,
    required this.catalogSettings,
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
  final Map<String, Object?> catalogSettings;
  final String websiteUrl;
  final AppProviderCategory category;
  final String notes;
  final String icon;
  final String iconColor;
  final int createdAt;
  final Map<String, Object?> meta;

  Map<String, Object?> get catalogEnv =>
      ClaudeSettingsParser.envFromSettings(catalogSettings);
}

/// Reads live Claude settings and CC Switch catalog for import.
class ClaudeCcSwitchImport {
  const ClaudeCcSwitchImport();

  Future<ClaudeRuntimeSnapshot> loadRuntime({
    Filesystem? fs,
    String? home,
  }) async {
    final store = fs ?? AppStorage.fs;
    final ctx = store.pathContext;
    final homeDir = (home ?? AppStorage.home).trim();
    if (homeDir.isEmpty) {
      return const ClaudeRuntimeSnapshot();
    }

    final settingsPath = ctx.join(homeDir, '.claude', 'settings.json');
    final liveSettings = await _readJsonObject(store, settingsPath) ?? const {};
    final liveEnv = ClaudeSettingsParser.envFromSettings(liveSettings);
    final takeover = ClaudeSettingsParser.detectProxyTakeover(liveEnv);

    final currentFromSettings = await _readCurrentClaudeProviderId(store, homeDir);
    final currentFromDb = currentFromSettings.isNotEmpty
        ? currentFromSettings
        : await _readCurrentClaudeProviderIdFromDb(store, homeDir);

    return ClaudeRuntimeSnapshot(
      liveSettings: liveSettings,
      proxyTakeover: takeover,
      currentProviderId: sanitizeImportedProviderId(currentFromDb),
    );
  }

  Future<List<CcSwitchClaudeCatalogRow>> loadCatalog({
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
    final tempDir = await Directory.systemTemp.createTemp('cc-switch-claude-');
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
        ['claude'],
      );
      final catalog = <CcSwitchClaudeCatalogRow>[];
      for (final row in rows) {
        final id = sanitizeImportedProviderId(row['id']?.toString() ?? '');
        if (id.isEmpty) continue;
        final settings = _jsonStringToMap(row['settings_config']);
        if (settings == null) continue;
        catalog.add(
          CcSwitchClaudeCatalogRow(
            id: id,
            name: row['name']?.toString() ?? id,
            catalogSettings: settings,
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
    ClaudeRuntimeSnapshot runtime,
    int now,
  ) {
    return ClaudeLiveImport.providerFromSettings(
      'default',
      runtime.liveSettings,
      now,
      meta: {
        'importSources': ['live'],
        if (runtime.proxyTakeover) 'proxyTakeover': true,
      },
    );
  }

  AppProviderConfig buildCatalogProvider({
    required CcSwitchClaudeCatalogRow row,
    required ClaudeRuntimeSnapshot runtime,
    required int now,
  }) {
    final isCurrent =
        row.id.isNotEmpty &&
        runtime.currentProviderId.isNotEmpty &&
        row.id == runtime.currentProviderId;
    final catalogEnv = row.catalogEnv;
    final liveEnv = runtime.liveEnv;
    final effectiveEnv = isCurrent
        ? _mergeClaudeEnv(
            catalogEnv: catalogEnv,
            liveEnv: liveEnv,
            proxyTakeover: runtime.proxyTakeover,
          )
        : catalogEnv;
    final upstreamEnv = isCurrent &&
            runtime.proxyTakeover &&
            catalogEnv.isNotEmpty &&
            effectiveEnv != catalogEnv
        ? catalogEnv
        : null;

    final effectiveSettings = <String, Object?>{
      ...row.catalogSettings,
      if (effectiveEnv.isNotEmpty) 'env': effectiveEnv,
    };

    final importSources = <String>['cc-switch'];
    if (isCurrent && runtime.hasLive) importSources.add('live');

    final meta = <String, Object?>{
      ...row.meta,
      'ccSwitchProviderId': row.id,
      'importSources': importSources,
      if (isCurrent && runtime.proxyTakeover) 'proxyTakeover': true,
    };

    final config = <String, Object?>{
      ...effectiveSettings,
      if (upstreamEnv != null && upstreamEnv.isNotEmpty) 'upstreamEnv': upstreamEnv,
      if (meta.isNotEmpty) 'meta': meta,
    };

    return ClaudeLiveImport.providerFromSettings(
      row.id,
      config,
      now,
      name: row.name,
      websiteUrl: row.websiteUrl,
      notes: row.notes,
      category: row.category,
      icon: row.icon,
      iconColor: row.iconColor,
      createdAt: row.createdAt,
      meta: meta,
    );
  }

  Map<String, Object?> _mergeClaudeEnv({
    required Map<String, Object?> catalogEnv,
    required Map<String, Object?> liveEnv,
    required bool proxyTakeover,
  }) {
    if (!proxyTakeover) {
      if (liveEnv.isNotEmpty) return Map<String, Object?>.from(liveEnv);
      return Map<String, Object?>.from(catalogEnv);
    }
    if (liveEnv.isEmpty) return Map<String, Object?>.from(catalogEnv);
    return Map<String, Object?>.from(liveEnv);
  }

  Future<String> _readCurrentClaudeProviderId(
    Filesystem store,
    String homeDir,
  ) async {
    final ctx = store.pathContext;
    final settingsPath = ctx.join(homeDir, '.cc-switch', 'settings.json');
    final settings = await _readJsonObject(store, settingsPath);
    final fromSettings = settings?['currentProviderClaude']?.toString() ?? '';
    if (fromSettings.trim().isNotEmpty) return fromSettings.trim();

    final configPath = ctx.join(homeDir, '.cc-switch', 'config.json');
    final config = await _readJsonObject(store, configPath);
    final fromConfig = config?['current_provider_claude']?.toString() ?? '';
    return fromConfig.trim();
  }

  Future<String> _readCurrentClaudeProviderIdFromDb(
    Filesystem store,
    String homeDir,
  ) async {
    final ctx = store.pathContext;
    final dbPath = ctx.join(homeDir, '.cc-switch', 'cc-switch.db');
    final bytes = await store.readBytes(dbPath);
    if (bytes == null || bytes.isEmpty) return '';

    Database? db;
    final tempDir = await Directory.systemTemp.createTemp('cc-switch-claude-current-');
    try {
      final tempFile = File(ctx.join(tempDir.path, 'cc-switch.db'));
      await tempFile.writeAsBytes(bytes);
      db = sqlite3.open(tempFile.path, mode: OpenMode.readOnly);
      final rows = db.select(
        "SELECT id FROM providers WHERE app_type = 'claude' AND is_current = 1 LIMIT 1",
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
}
