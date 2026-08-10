import 'dart:convert';

import '../../models/plugin.dart';
import '../../utils/lock_pool.dart';
import '../../utils/logging/logger.dart';
import '../cli/registry/capabilities/plugin_manifest_paths.dart';
import '../cli/registry/capabilities/plugin_provisioner_capability.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import 'cli_plugin_layout.dart';
import 'cli_plugin_provision_cache.dart';
import 'plugin_bundle_resolver.dart';

/// Result of reconciling one session plugin pool.
class PluginBundlePoolResult {
  const PluginBundlePoolResult({
    this.linked = const [],
    this.skippedMissingIds = const [],
    this.errors = const [],
    this.memberProvisionStampJson,
  });

  final List<String> linked;
  final List<String> skippedMissingIds;
  final List<String> errors;

  /// Member provision stamp JSON, for the writer's registry invalidation.
  final String? memberProvisionStampJson;
}

/// The only component that fills a session's plugin pool (`bundlePoolDir`).
///
/// Sources every enabled bundle from the app-level installed root
/// (`<teampilotRoot>/plugins/installed/<directory>`), materializes it into the
/// pool with the target CLI's flavor projected, and reconciles stale entries.
///
/// Layer-agnostic: Simple, native, and mixed launches all drive this service
/// from the merged `runtimeBundle.pluginIds`, so a plugin enabled at any layer
/// (team > expert > workspace) reaches the session exactly the same way.
class PluginBundlePoolService {
  PluginBundlePoolService({
    required Filesystem fs,
    String? teampilotRoot,
    String? sourceRoot,
  }) : _fs = fs,
       _sourceRoot =
           sourceRoot ??
           (teampilotRoot == null || teampilotRoot.isEmpty
               ? throw ArgumentError('teampilotRoot or sourceRoot required')
               : AppPaths.pluginsDirForTeampilotRoot(teampilotRoot));

  final Filesystem _fs;
  final String _sourceRoot;

  /// Entries inside the pool dir that the writer manages, never bundles.
  static const _managedNames = {'marketplaces'};

  static final LockPool _reconcileLocks = LockPool();

  Future<PluginBundlePoolResult> reconcile({
    required String poolDir,
    required List<String> enabledPluginIds,
    required List<Plugin> installedCatalog,
    PluginManifestPaths paths = neutralPluginManifestPaths,
  }) {
    return _reconcileLocks.synchronized(
      poolDir,
      () => _reconcileUnlocked(
        poolDir: poolDir,
        enabledPluginIds: enabledPluginIds,
        installedCatalog: installedCatalog,
        paths: paths,
      ),
    );
  }

  Future<PluginBundlePoolResult> _reconcileUnlocked({
    required String poolDir,
    required List<String> enabledPluginIds,
    required List<Plugin> installedCatalog,
    required PluginManifestPaths paths,
  }) async {
    final total = Stopwatch()..start();
    final resolved = PluginBundleResolver.resolve(
      enabledPluginIds: enabledPluginIds,
      installedCatalog: installedCatalog,
    );

    // Fast path: the saved member stamp already reflects the desired enabled
    // bundles (by directory/name/version), so nothing changed and the pool
    // needs no reconcile. Idempotent across repeated launches.
    final savedStampJson = await CliPluginProvisionCache.memberProvisionStampJson(
      fs: _fs,
      memberPluginsDir: poolDir,
    );
    if (savedStampJson.isNotEmpty &&
        _stampMatchesDesired(savedStampJson, resolved.enabled, paths)) {
      appLogger.d(
        '[session-launch] plugin-pool stamp-hit '
        'enabled=${resolved.enabled.length} ms=${total.elapsedMilliseconds}',
      );
      return PluginBundlePoolResult(
        linked: const [],
        skippedMissingIds: resolved.skippedMissingIds,
        memberProvisionStampJson: savedStampJson,
      );
    }

    final ctx = _fs.pathContext;
    final linked = <String>[];
    final errors = <String>[];
    final bundles = <Map<String, Object?>>[];
    final usedNames = <String>{};

    if ((await _fs.stat(poolDir)).exists) {
      // Clear stale bundle entries; keep writer-managed entries
      // (`marketplaces/`, `known_marketplaces.json`, `installed_plugins.json`)
      // and provision stamps (dot-files).
      for (final entry in await _fs.listDir(poolDir)) {
        if (entry.name.startsWith('.')) continue;
        if (_managedNames.contains(entry.name)) continue;
        final path = ctx.join(poolDir, entry.name);
        final stat = await _fs.stat(path);
        if (!(stat.isDirectory || stat.isSymlink)) continue;
        await _fs.removeRecursive(path);
      }
    }
    await _fs.ensureDir(poolDir);

    for (final plugin in resolved.enabled) {
      var linkName = plugin.directory.trim();
      if (linkName.isEmpty) linkName = plugin.name;
      if (usedNames.contains(linkName)) {
        final owner = plugin.marketplaceOwner?.trim();
        linkName = '${owner != null && owner.isNotEmpty ? owner : 'local'}__$linkName';
      }
      usedNames.add(linkName);

      final sourceDir = ctx.join(_sourceRoot, plugin.directory);
      final root = await CliPluginLayout.resolvePluginRoot(
        _fs,
        sourceDir,
        paths: neutralPluginManifestPaths,
      );
      if (root == null) {
        errors.add('${plugin.id}: no plugin manifest under $sourceDir');
        continue;
      }
      final dest = ctx.join(poolDir, linkName);
      final pluginSw = Stopwatch()..start();
      try {
        if ((await _fs.stat(dest)).exists) {
          await _fs.removeRecursive(dest);
        }
        var linkedNow = await CliPluginLayout.linkOrCopyTree(
          fs: _fs,
          source: root,
          destination: dest,
        );
        // Prefer keeping the session pool as a symlink into the shared
        // installed bundle. Flavor projection seeds the *installed* root once
        // when missing — never a per-session full copyTree of large plugins.
        final needsFlavor =
            paths.manifestDirName !=
            neutralPluginManifestPaths.manifestDirName;
        var seededFlavorIntoInstalled = false;
        final projectSw = Stopwatch()..start();
        if (needsFlavor) {
          final flavorReady = (await _fs.stat(
            ctx.join(root, paths.manifestRelativePath),
          )).isFile;
          if (linkedNow) {
            if (!flavorReady) {
              await CliPluginLayout.projectBundleToFlavor(_fs, root, paths);
              seededFlavorIntoInstalled = true;
            }
          } else {
            // Symlink unavailable — project into the session copy.
            await CliPluginLayout.projectBundleToFlavor(_fs, dest, paths);
            if (paths.manifestDirName ==
                claudePluginManifestPaths.manifestDirName) {
              await CliPluginLayout.removeManifestDir(
                _fs,
                dest,
                flashskyaiPluginManifestPaths.manifestDirName,
              );
            }
          }
        }
        appLogger.d(
          '[session-launch] plugin-pool materialize '
          'id=${plugin.id} keptSymlink=$linkedNow '
          'seededFlavor=$seededFlavorIntoInstalled '
          'projectMs=${projectSw.elapsedMilliseconds} '
          'ms=${pluginSw.elapsedMilliseconds}',
        );
        final rootStat = await _fs.stat(root);
        bundles.add({
          'dirName': linkName,
          'teamEntryName': plugin.directory,
          'name': plugin.name,
          'version': plugin.version,
          'mtimeMs': rootStat.mtime?.millisecondsSinceEpoch ?? 0,
        });
        linked.add(linkName);
      } catch (e) {
        errors.add('${plugin.id}: $e');
      }
    }

    final sourceStat = await _fs.stat(_sourceRoot);
    await CliPluginProvisionCache.writeMemberProvisionStamp(
      fs: _fs,
      teamPluginsDir: _sourceRoot,
      memberPluginsDir: poolDir,
      paths: paths,
      bundles: bundles,
      teamPluginsMtimeMs: sourceStat.mtime?.millisecondsSinceEpoch ?? 0,
    );
    final stampJson = await CliPluginProvisionCache.memberProvisionStampJson(
      fs: _fs,
      memberPluginsDir: poolDir,
    );

    appLogger.d(
      '[session-launch] plugin-pool done '
      'linked=${linked.length} errors=${errors.length} '
      'ms=${total.elapsedMilliseconds}',
    );
    return PluginBundlePoolResult(
      linked: linked,
      skippedMissingIds: resolved.skippedMissingIds,
      errors: errors,
      memberProvisionStampJson: stampJson,
    );
  }

  /// Whether a saved member stamp already matches the desired enabled bundles.
  ///
  /// Compares bundle identity (directory/name/version) so a source bundle whose
  /// manifest was only available in a neutral flavor still resolves — no source
  /// mtime / flavor probing is needed for the fast path.
  static bool _stampMatchesDesired(
    String stampJson,
    List<Plugin> enabled,
    PluginManifestPaths paths,
  ) {
    Map<String, Object?>? root;
    try {
      final decoded = jsonDecode(stampJson);
      if (decoded is Map) root = decoded.cast<String, Object?>();
    } on Object {
      return false;
    }
    if (root == null) return false;
    if (root['flavor'] != paths.manifestDirName) return false;

    final bundles = (root['bundles'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => m.cast<String, Object?>())
        .toList();
    if (bundles.length != enabled.length) return false;

    for (final plugin in enabled) {
      final linkName = plugin.directory.trim().isNotEmpty
          ? plugin.directory.trim()
          : plugin.name;
      var matched = false;
      for (final bundle in bundles) {
        if (bundle['dirName'] == linkName &&
            bundle['name'] == plugin.name &&
            bundle['version'] == plugin.version) {
          matched = true;
          break;
        }
      }
      if (!matched) return false;
    }
    return true;
  }
}
