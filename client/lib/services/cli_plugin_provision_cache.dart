import 'dart:convert';

import '../models/plugin.dart';
import 'cli_plugin_layout.dart';
import 'cli_plugin_manifest_flavor.dart';
import 'io/filesystem.dart';

/// Fingerprints for skipping redundant plugin copy / registry writes on session launch.
class CliPluginProvisionCache {
  CliPluginProvisionCache._();

  static const memberStampFileName = '.teampilot-member-plugins-stamp.json';
  static const registryStampFileName = '.teampilot-registry-stamp.json';
  static const marketplaceSourceStampFileName =
      '.teampilot-marketplace-source-stamp.json';
  static const stampVersion = 1;

  /// True when [memberPluginsDir] already reflects [teamPluginsDir] for [flavor].
  static Future<bool> isMemberProvisionCurrent({
    required Filesystem fs,
    required String teamPluginsDir,
    required String memberPluginsDir,
    required CliPluginManifestFlavor flavor,
  }) async {
    final stampPath = fs.pathContext.join(memberPluginsDir, memberStampFileName);
    final saved = await _readStamp(fs, stampPath);
    if (saved == null) return false;

    final current = await buildMemberProvisionStamp(
      fs: fs,
      teamPluginsDir: teamPluginsDir,
      flavor: flavor,
    );
    if (!_stampsEqual(saved, current)) return false;

    final bundles = (saved['bundles'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => m.cast<String, Object?>())
        .toList();
    for (final bundle in bundles) {
      final dirName = bundle['dirName'] as String?;
      if (dirName == null || dirName.isEmpty) continue;
      final dest = fs.pathContext.join(memberPluginsDir, dirName);
      final stat = await fs.stat(dest);
      if (!stat.isDirectory && !stat.isSymlink) return false;
    }
    return true;
  }

  static Future<void> writeMemberProvisionStamp({
    required Filesystem fs,
    required String teamPluginsDir,
    required String memberPluginsDir,
    required CliPluginManifestFlavor flavor,
  }) async {
    final stamp = await buildMemberProvisionStamp(
      fs: fs,
      teamPluginsDir: teamPluginsDir,
      flavor: flavor,
    );
    await fs.ensureDir(memberPluginsDir);
    await fs.atomicWrite(
      fs.pathContext.join(memberPluginsDir, memberStampFileName),
      const JsonEncoder.withIndent('  ').convert(stamp),
    );
  }

  static Future<Map<String, Object?>> buildMemberProvisionStamp({
    required Filesystem fs,
    required String teamPluginsDir,
    required CliPluginManifestFlavor flavor,
  }) async {
    final bundles = <Map<String, Object?>>[];
    final teamStat = await fs.stat(teamPluginsDir);
    if (teamStat.isDirectory) {
      final ctx = fs.pathContext;
      for (final entry in await fs.listDir(teamPluginsDir)) {
        if (entry.name.startsWith('.')) continue;
        final source = ctx.join(teamPluginsDir, entry.name);
        if (!await CliPluginLayout.isPluginBundleEntry(fs, source)) continue;
        final root = await CliPluginLayout.resolvePluginRoot(
          fs,
          source,
          flavor: flavor,
        );
        if (root == null) continue;
        final manifest = await CliPluginLayout.readManifest(
          fs,
          root,
          flavor: flavor,
        );
        final dirName = await CliPluginLayout.bundleDirName(
          fs,
          root,
          flavor: flavor,
        );
        final rootStat = await fs.stat(root);
        bundles.add({
          'dirName': dirName,
          'name': manifest?.name ?? dirName,
          'version': manifest?.version ?? '0.0.0',
          'mtimeMs': rootStat.mtime?.millisecondsSinceEpoch ?? 0,
        });
      }
    }
    bundles.sort((a, b) => (a['dirName'] as String).compareTo(b['dirName'] as String));
    return {
      'version': stampVersion,
      'flavor': flavor.name,
      'bundles': bundles,
    };
  }

  /// True when registry artifacts under [pluginsDir] match current inputs.
  static Future<bool> isRegistryCurrent({
    required Filesystem fs,
    required String pluginsDir,
    required String configDir,
    required String tool,
    required CliPluginManifestFlavor flavor,
    required String memberProvisionStampJson,
    required List<String> enabledPluginIds,
    required List<Plugin> catalog,
    required List<Map<String, Object?>> marketplaceSourceStamps,
  }) async {
    final stampPath = fs.pathContext.join(pluginsDir, registryStampFileName);
    final saved = await _readStamp(fs, stampPath);
    if (saved == null) return false;

    final current = buildRegistryStamp(
      tool: tool,
      flavor: flavor,
      memberProvisionStampJson: memberProvisionStampJson,
      enabledPluginIds: enabledPluginIds,
      catalog: catalog,
      marketplaceSourceStamps: marketplaceSourceStamps,
    );
    if (!_stampsEqual(saved, current)) return false;

    final installed = fs.pathContext.join(pluginsDir, 'installed_plugins.json');
    if (!(await fs.stat(installed)).isFile) return false;

    final settings = fs.pathContext.join(configDir, 'settings.json');
    if (!(await fs.stat(settings)).isFile) return false;

    return true;
  }

  static Future<void> writeRegistryStamp({
    required Filesystem fs,
    required String pluginsDir,
    required String tool,
    required CliPluginManifestFlavor flavor,
    required String memberProvisionStampJson,
    required List<String> enabledPluginIds,
    required List<Plugin> catalog,
    required List<Map<String, Object?>> marketplaceSourceStamps,
  }) async {
    await fs.ensureDir(pluginsDir);
    await fs.atomicWrite(
      fs.pathContext.join(pluginsDir, registryStampFileName),
      const JsonEncoder.withIndent('  ').convert(
        buildRegistryStamp(
          tool: tool,
          flavor: flavor,
          memberProvisionStampJson: memberProvisionStampJson,
          enabledPluginIds: enabledPluginIds,
          catalog: catalog,
          marketplaceSourceStamps: marketplaceSourceStamps,
        ),
      ),
    );
  }

  static Map<String, Object?> buildRegistryStamp({
    required String tool,
    required CliPluginManifestFlavor flavor,
    required String memberProvisionStampJson,
    required List<String> enabledPluginIds,
    required List<Plugin> catalog,
    required List<Map<String, Object?>> marketplaceSourceStamps,
  }) {
    final ids = [...enabledPluginIds]..sort();
    final catalogLines = catalog
        .map((p) => '${p.id}:${p.version}:${p.updatedAt}')
        .toList()
      ..sort();
    final markets = [...marketplaceSourceStamps]
      ..sort((a, b) => (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));
    return {
      'version': stampVersion,
      'tool': tool,
      'flavor': flavor.name,
      'memberProvision': memberProvisionStampJson,
      'enabledPluginIds': ids,
      'catalog': catalogLines,
      'marketplaces': markets,
    };
  }

  static Future<String> memberProvisionStampJson({
    required Filesystem fs,
    required String memberPluginsDir,
  }) async {
    final stampPath = fs.pathContext.join(memberPluginsDir, memberStampFileName);
    final text = await fs.readString(stampPath);
    if (text == null || text.trim().isEmpty) {
      return '';
    }
    return text.trim();
  }

  /// Skips [copyTree] when session marketplace dir already matches git cache.
  static Future<bool> isMarketplaceMaterializationCurrent({
    required Filesystem fs,
    required String dest,
    required String teampilotCacheDir,
  }) async {
    final ctx = fs.pathContext;
    final manifestPath = ctx.join(
      dest,
      CliPluginManifestFlavor.claude.manifestDirName,
      'marketplace.json',
    );
    if (!(await fs.stat(manifestPath)).isFile) return false;

    final stampPath = ctx.join(dest, marketplaceSourceStampFileName);
    final saved = await _readStamp(fs, stampPath);
    if (saved == null) return false;

    final cacheStat = await fs.stat(teampilotCacheDir);
    if (!cacheStat.isDirectory) return false;

    return saved['sourcePath'] == teampilotCacheDir &&
        saved['sourceMtimeMs'] == (cacheStat.mtime?.millisecondsSinceEpoch ?? 0);
  }

  static Future<void> writeMarketplaceSourceStamp({
    required Filesystem fs,
    required String dest,
    required String teampilotCacheDir,
  }) async {
    final cacheStat = await fs.stat(teampilotCacheDir);
    await fs.atomicWrite(
      fs.pathContext.join(dest, marketplaceSourceStampFileName),
      const JsonEncoder.withIndent('  ').convert({
        'version': stampVersion,
        'sourcePath': teampilotCacheDir,
        'sourceMtimeMs': cacheStat.mtime?.millisecondsSinceEpoch ?? 0,
      }),
    );
  }

  static Map<String, Object?> marketplaceSourceStampEntry({
    required String name,
    required String teampilotCacheDir,
    required int sourceMtimeMs,
  }) {
    return {
      'name': name,
      'sourcePath': teampilotCacheDir,
      'sourceMtimeMs': sourceMtimeMs,
    };
  }

  static Future<Map<String, Object?>?> _readStamp(
    Filesystem fs,
    String path,
  ) async {
    final text = await fs.readString(path);
    if (text == null || text.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return Map<String, Object?>.from(
          decoded.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } on Object {
      return null;
    }
    return null;
  }

  static bool _stampsEqual(Map<String, Object?> a, Map<String, Object?> b) {
    return jsonEncode(_canonicalize(a)) == jsonEncode(_canonicalize(b));
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      return {
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) {
      return value.map(_canonicalize).toList();
    }
    return value;
  }
}
