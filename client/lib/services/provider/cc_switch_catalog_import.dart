import 'dart:convert';
import 'dart:io' show Directory, File;

import 'package:sqlite3/sqlite3.dart';

import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../io/filesystem.dart';
import 'codex/codex_cc_switch_import.dart';

/// Reads provider rows from `~/.cc-switch/cc-switch.db`.
final class CcSwitchCatalogImport {
  const CcSwitchCatalogImport();

  Future<List<CcSwitchCatalogRow>> loadRows({
    required CliTool cli,
    required Filesystem fs,
    required String homeDirectory,
  }) async {
    final home = homeDirectory.trim();
    if (home.isEmpty) return const [];

    final dbPath = fs.pathContext.join(home, '.cc-switch', 'cc-switch.db');
    final bytes = await fs.readBytes(dbPath);
    if (bytes == null || bytes.isEmpty) return const [];

    Database? db;
    final tempDir = await Directory.systemTemp.createTemp('cc-switch-');
    try {
      final tempFile = File(fs.pathContext.join(tempDir.path, 'cc-switch.db'));
      await tempFile.writeAsBytes(bytes);
      db = sqlite3.open(tempFile.path, mode: OpenMode.readOnly);
      final rows = db.select(
        '''
SELECT id, name, settings_config, website_url, category, created_at,
       notes, icon, icon_color, meta
FROM providers
WHERE app_type = ?
''',
        [cli.value],
      );
      return [
        for (final row in rows)
          CcSwitchCatalogRow(
            id: sanitizeImportedProviderId(row['id']?.toString() ?? ''),
            name: row['name']?.toString() ?? '',
            settingsConfig: _jsonStringToMap(row['settings_config']) ?? const {},
            websiteUrl: row['website_url']?.toString() ?? '',
            category: AppProviderCategory.fromJson(row['category']),
            createdAt: (row['created_at'] as int?) ?? 0,
            notes: row['notes']?.toString() ?? '',
            icon: row['icon']?.toString() ?? '',
            iconColor: row['icon_color']?.toString() ?? '',
            meta: _jsonStringToMap(row['meta']) ?? const {},
          ),
      ];
    } on Object {
      return const [];
    } finally {
      db?.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }
}

final class CcSwitchCatalogRow {
  const CcSwitchCatalogRow({
    required this.id,
    required this.name,
    required this.settingsConfig,
    this.websiteUrl = '',
    this.category = AppProviderCategory.custom,
    this.createdAt = 0,
    this.notes = '',
    this.icon = '',
    this.iconColor = '',
    this.meta = const {},
  });

  final String id;
  final String name;
  final Map<String, Object?> settingsConfig;
  final String websiteUrl;
  final AppProviderCategory category;
  final int createdAt;
  final String notes;
  final String icon;
  final String iconColor;
  final Map<String, Object?> meta;
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
