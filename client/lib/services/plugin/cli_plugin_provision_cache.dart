import 'dart:convert';
import '../../models/plugin.dart';
import 'cli_plugin_layout.dart';
import '../cli/registry/capabilities/plugin_manifest_capability.dart';
import '../io/filesystem.dart';

/// Fingerprints for skipping redundant plugin copy / registry writes on session launch.
class CliPluginProvisionCache {
  CliPluginProvisionCache._();

  static const memberStampFileName = '.teampilot-member-plugins-stamp.json';
  static const registryStampFileName = '.teampilot-registry-stamp.json';
  static const marketplaceSourceStampFileName =
      '.teampilot-marketplace-source-stamp.json';
  static const pluginCacheMetaFileName = '.teampilot-plugin-cache-meta.json';
  static const stampVersion = 1;

  static String? _cachedTeamStampKey;
  static Map<String, Object?>? _cachedTeamStamp;
  static final Map<String, String> _memberStampJsonCache = {};

  /// True when [memberPluginsDir] already reflects [teamPluginsDir] for [flavor].
  static Future<bool> isMemberProvisionCurrent({
    required Filesystem fs,
    required String teamPluginsDir,
    required String memberPluginsDir,
    required PluginManifestPaths paths,
  }) async {
    final skipped = await trySkipMemberProvision(
      fs: fs,
      teamPluginsDir: teamPluginsDir,
      memberPluginsDir: memberPluginsDir,
      paths: paths,
    );
    return skipped != null;
  }

  /// Skips copying when member plugins already match team bundles.
  ///
  /// Returns member provision stamp JSON, or `null` when a full reprovision is
  /// needed.
  static Future<String?> trySkipMemberProvision({
    required Filesystem fs,
    required String teamPluginsDir,
    required String memberPluginsDir,
    required PluginManifestPaths paths,
  }) async {
    final stampPath = fs.pathContext.join(memberPluginsDir, memberStampFileName);
    final saved = await _readStamp(fs, stampPath);
    if (saved == null) {
      return null;
    }

    if (saved['flavor'] != paths.manifestDirName) {
      return null;
    }

    if (!await _memberBundlesMatchSavedStamp(
      fs: fs,
      memberPluginsDir: memberPluginsDir,
      saved: saved,
    )) {
      return null;
    }

    final teamMatches = await _savedBundlesMatchTeamMtimes(
      fs: fs,
      teamPluginsDir: teamPluginsDir,
      saved: saved,
      paths: paths,
    );
    if (!teamMatches) {
      return null;
    }

    if (saved['teamPluginsDir'] != teamPluginsDir ||
        saved['teamPluginsMtimeMs'] == null ||
        _stampMissingTeamEntryNames(saved)) {
      return null;
    }

    return memberProvisionStampJson(
      fs: fs,
      memberPluginsDir: memberPluginsDir,
    );
  }

  static bool _stampMissingTeamEntryNames(Map<String, Object?> saved) {
    final bundles = saved['bundles'] as List? ?? const [];
    for (final bundle in bundles) {
      if (bundle is! Map) continue;
      final name = bundle['teamEntryName'] as String?;
      if (name == null || name.isEmpty) return true;
    }
    return false;
  }

  /// Verifies saved bundle fingerprints against team sources (stat only).
  static Future<bool> _savedBundlesMatchTeamMtimes({
    required Filesystem fs,
    required String teamPluginsDir,
    required Map<String, Object?> saved,
    required PluginManifestPaths paths,
  }) async {
    final bundles = (saved['bundles'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => m.cast<String, Object?>())
        .toList();
    if (bundles.isEmpty) {
      final teamStat = await fs.stat(teamPluginsDir);
      return !teamStat.isDirectory;
    }

    final ctx = fs.pathContext;
    final checks = bundles.map((bundle) async {
      final expectedMtime = bundle['mtimeMs'] as int?;
      if (expectedMtime == null) return false;

      final teamEntryName = bundle['teamEntryName'] as String?;
      final String? source;
      if (teamEntryName != null && teamEntryName.isNotEmpty) {
        source = ctx.join(teamPluginsDir, teamEntryName);
        if (!await CliPluginLayout.isPluginBundleEntry(fs, source)) {
          return false;
        }
      } else {
        final resolved = await _resolveTeamBundleSource(
          fs: fs,
          teamPluginsDir: teamPluginsDir,
          bundle: bundle,
          paths: paths,
        );
        if (resolved == null) return false;
        source = resolved;
      }

      final root = await CliPluginLayout.resolvePluginRoot(
        fs,
        source,
        paths: paths,
      );
      if (root == null) return false;
      final rootStat = await fs.stat(root);
      if ((rootStat.mtime?.millisecondsSinceEpoch ?? 0) != expectedMtime) {
        return false;
      }
      final expectedVersion = bundle['version'] as String?;
      if (expectedVersion == null) return true;
      final manifest = await CliPluginLayout.readManifest(
        fs,
        root,
        paths: paths,
      );
      return manifest?.version == expectedVersion;
    });
    final results = await Future.wait(checks);
    return results.every((ok) => ok);
  }

  static Future<String?> _resolveTeamBundleSource({
    required Filesystem fs,
    required String teamPluginsDir,
    required Map<String, Object?> bundle,
    required PluginManifestPaths paths,
  }) async {
    final ctx = fs.pathContext;
    final teamEntryName = bundle['teamEntryName'] as String?;
    if (teamEntryName != null && teamEntryName.isNotEmpty) {
      final direct = ctx.join(teamPluginsDir, teamEntryName);
      if (await CliPluginLayout.isPluginBundleEntry(fs, direct)) {
        return direct;
      }
    }

    final dirName = bundle['dirName'] as String?;
    if (dirName == null || dirName.isEmpty) return null;

    for (final entry in await fs.listDir(teamPluginsDir)) {
      if (entry.name.startsWith('.')) continue;
      final child = ctx.join(teamPluginsDir, entry.name);
      if (!await CliPluginLayout.isPluginBundleEntry(fs, child)) continue;
      final root = await CliPluginLayout.resolvePluginRoot(
        fs,
        child,
        paths: paths,
      );
      if (root == null) continue;
      final name = await CliPluginLayout.bundleDirName(
        fs,
        root,
        paths: paths,
      );
      if (name == dirName) return child;
    }
    return null;
  }

  static Future<bool> _memberBundlesMatchSavedStamp({
    required Filesystem fs,
    required String memberPluginsDir,
    required Map<String, Object?> saved,
  }) async {
    final bundles = (saved['bundles'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => m.cast<String, Object?>())
        .toList();
    if (bundles.isEmpty) return true;

    final checks = bundles.map((bundle) async {
      final dirName = bundle['dirName'] as String?;
      if (dirName == null || dirName.isEmpty) return false;
      final dest = fs.pathContext.join(memberPluginsDir, dirName);
      final stat = await fs.stat(dest);
      return stat.isDirectory || stat.isSymlink;
    });
    final results = await Future.wait(checks);
    return results.every((ok) => ok);
  }

  static Future<Map<String, Object?>> buildMemberProvisionStampCached({
    required Filesystem fs,
    required String teamPluginsDir,
    required PluginManifestPaths paths,
  }) async {
    final key = '$teamPluginsDir:${paths.manifestDirName}';
    if (_cachedTeamStampKey == key && _cachedTeamStamp != null) {
      return _cachedTeamStamp!;
    }
    final stamp = await buildMemberProvisionStamp(
      fs: fs,
      teamPluginsDir: teamPluginsDir,
      paths: paths,
    );
    _cachedTeamStampKey = key;
    _cachedTeamStamp = stamp;
    return stamp;
  }

  static void _invalidateTeamStampCache() {
    _cachedTeamStampKey = null;
    _cachedTeamStamp = null;
  }

  static void _invalidateMemberStampJsonCache(String memberPluginsDir) {
    _memberStampJsonCache.remove(memberPluginsDir);
  }

  static Map<String, Object?> memberProvisionStampFromBundles({
    required String teamPluginsDir,
    required int teamPluginsMtimeMs,
    required PluginManifestPaths paths,
    required List<Map<String, Object?>> bundles,
  }) {
    final sorted = List<Map<String, Object?>>.from(bundles)
      ..sort((a, b) => (a['dirName'] as String).compareTo(b['dirName'] as String));
    return {
      'version': stampVersion,
      'flavor': paths.manifestDirName,
      'teamPluginsDir': teamPluginsDir,
      'teamPluginsMtimeMs': teamPluginsMtimeMs,
      'bundles': sorted,
    };
  }

  static Future<void> writeMemberProvisionStamp({
    required Filesystem fs,
    required String teamPluginsDir,
    required String memberPluginsDir,
    required PluginManifestPaths paths,
    List<Map<String, Object?>>? bundles,
    int? teamPluginsMtimeMs,
  }) async {
    final stamp = bundles != null && teamPluginsMtimeMs != null
        ? memberProvisionStampFromBundles(
            teamPluginsDir: teamPluginsDir,
            teamPluginsMtimeMs: teamPluginsMtimeMs,
            paths: paths,
            bundles: bundles,
          )
        : await buildMemberProvisionStamp(
            fs: fs,
            teamPluginsDir: teamPluginsDir,
            paths: paths,
          );
    await fs.ensureDir(memberPluginsDir);
    await fs.atomicWrite(
      fs.pathContext.join(memberPluginsDir, memberStampFileName),
      const JsonEncoder.withIndent('  ').convert(stamp),
    );
    _invalidateTeamStampCache();
    _invalidateMemberStampJsonCache(memberPluginsDir);
    _memberStampJsonCache[memberPluginsDir] =
        const JsonEncoder.withIndent('  ').convert(stamp);
  }

  static Future<Map<String, Object?>> buildMemberProvisionStamp({
    required Filesystem fs,
    required String teamPluginsDir,
    required PluginManifestPaths paths,
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
          paths: paths,
        );
        if (root == null) continue;
        final manifest = await CliPluginLayout.readManifest(
          fs,
          root,
          paths: paths,
        );
        final dirName = await CliPluginLayout.bundleDirName(
          fs,
          root,
          paths: paths,
        );
        final rootStat = await fs.stat(root);
        bundles.add({
          'dirName': dirName,
          'teamEntryName': entry.name,
          'name': manifest?.name ?? dirName,
          'version': manifest?.version ?? '0.0.0',
          'mtimeMs': rootStat.mtime?.millisecondsSinceEpoch ?? 0,
        });
      }
    }
    bundles.sort((a, b) => (a['dirName'] as String).compareTo(b['dirName'] as String));
    return {
      'version': stampVersion,
      'flavor': paths.manifestDirName,
      'teamPluginsDir': teamPluginsDir,
      'teamPluginsMtimeMs': teamStat.mtime?.millisecondsSinceEpoch ?? 0,
      'bundles': bundles,
    };
  }

  /// True when registry artifacts under [pluginsDir] match current inputs.
  static Future<bool> isRegistryCurrent({
    required Filesystem fs,
    required String pluginsDir,
    required String configDir,
    required String tool,
    required PluginManifestPaths paths,
    required String memberProvisionStampJson,
    required List<String> enabledPluginIds,
    required List<Plugin> catalog,
    required List<Map<String, Object?>> marketplaceSourceStamps,
  }) async {
    final stampPath = fs.pathContext.join(pluginsDir, registryStampFileName);
    final saved = await _readStamp(fs, stampPath);
    if (saved == null) {
      return false;
    }

    final current = buildRegistryStamp(
      tool: tool,
      paths: paths,
      memberProvisionStampJson: memberProvisionStampJson,
      enabledPluginIds: enabledPluginIds,
      catalog: catalog,
      marketplaceSourceStamps: marketplaceSourceStamps,
    );
    if (!_stampsEqual(_registryStampForCompare(saved), current)) {
      return false;
    }

    final installed = fs.pathContext.join(pluginsDir, 'installed_plugins.json');
    if (!(await fs.stat(installed)).isFile) {
      return false;
    }

    final settings = fs.pathContext.join(configDir, 'settings.json');
    if (!(await fs.stat(settings)).isFile) {
      return false;
    }

    return true;
  }

  static Future<void> writeRegistryStamp({
    required Filesystem fs,
    required String pluginsDir,
    required String tool,
    required PluginManifestPaths paths,
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
          paths: paths,
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
    required PluginManifestPaths paths,
    required String memberProvisionStampJson,
    required List<String> enabledPluginIds,
    required List<Plugin> catalog,
    required List<Map<String, Object?>> marketplaceSourceStamps,
  }) {
    final ids = [...enabledPluginIds]..sort();
    final catalogLines = catalog
        .map((p) => '${p.id}:${p.version}')
        .toList()
      ..sort();
    final markets = [...marketplaceSourceStamps]
      ..sort((a, b) => (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));
    return {
      'version': stampVersion,
      'tool': tool,
      'flavor': paths.manifestDirName,
      'memberProvision': provisionFingerprintForRegistry(memberProvisionStampJson),
      'enabledPluginIds': ids,
      'catalog': catalogLines,
      'marketplaces': markets,
    };
  }

  /// Bundle-level fingerprint for registry skip (ignores metadata-only stamp fields).
  static String provisionFingerprintForRegistry(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return normalizeProvisionJson(raw);
      final root = decoded.cast<String, Object?>();
      final bundles = (root['bundles'] as List? ?? const [])
          .whereType<Map>()
          .map((m) {
            final bundle = m.cast<String, Object?>();
            return {
              'dirName': bundle['dirName'],
              'name': bundle['name'],
              'version': bundle['version'],
              'mtimeMs': bundle['mtimeMs'],
            };
          })
          .toList()
        ..sort(
          (a, b) => (a['dirName'] as String? ?? '')
              .compareTo(b['dirName'] as String? ?? ''),
        );
      return jsonEncode(_canonicalize({
        'version': root['version'],
        'flavor': root['flavor'],
        'bundles': bundles,
      }));
    } on Object {
      return normalizeProvisionJson(raw);
    }
  }

  static Map<String, Object?> _registryStampForCompare(
    Map<String, Object?> saved,
  ) {
    final memberProvision = saved['memberProvision'];
    if (memberProvision is! String) return saved;
    return Map<String, Object?>.from(saved)
      ..['memberProvision'] = provisionFingerprintForRegistry(memberProvision);
  }

  /// Canonical JSON for comparing member provision stamps across formatting.
  static String normalizeProvisionJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    try {
      final decoded = jsonDecode(trimmed);
      return jsonEncode(_canonicalize(decoded));
    } on Object {
      return trimmed;
    }
  }

  /// Stable marketplace fingerprint: git commit SHA when meta exists, else mtime.
  static Future<Map<String, Object?>?> marketplaceSourceStampFromCacheDir({
    required Filesystem fs,
    required String name,
    required String cacheDir,
  }) async {
    final cacheStat = await fs.stat(cacheDir);
    if (!cacheStat.isDirectory) return null;

    final metaPath = fs.pathContext.join(cacheDir, pluginCacheMetaFileName);
    final meta = await _readStamp(fs, metaPath);
    final commitSha = meta?['commitSha'] as String?;
    if (commitSha != null && commitSha.isNotEmpty) {
      return {
        'name': name,
        'sourcePath': cacheDir,
        'commitSha': commitSha,
      };
    }

    return marketplaceSourceStampEntry(
      name: name,
      teampilotCacheDir: cacheDir,
      sourceMtimeMs: cacheStat.mtime?.millisecondsSinceEpoch ?? 0,
    );
  }

  static Future<String> memberProvisionStampJson({
    required Filesystem fs,
    required String memberPluginsDir,
  }) async {
    final cached = _memberStampJsonCache[memberPluginsDir];
    if (cached != null) return cached;

    final stampPath = fs.pathContext.join(memberPluginsDir, memberStampFileName);
    final text = await fs.readString(stampPath);
    if (text == null || text.trim().isEmpty) {
      return '';
    }
    final normalized = text.trim();
    _memberStampJsonCache[memberPluginsDir] = normalized;
    return normalized;
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
      claudePluginManifestPaths.manifestDirName,
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
