import '../../models/plugin.dart';
import '../../utils/logger.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_layout.dart';
import 'cli_plugin_layout.dart';
import '../cli/registry/capabilities/plugin_manifest_capability.dart';
import '../storage/storage_resolver.dart';
import '../io/filesystem.dart';

class TeamPluginSyncResult {
  const TeamPluginSyncResult({
    this.linked = const [],
    this.skippedMissingIds = const [],
    this.errors = const [],
    this.conflictResolutions = const [],
  });

  final List<String> linked;
  final List<String> skippedMissingIds;
  final List<String> errors;
  final List<(String, String)> conflictResolutions;

  bool get ok => errors.isEmpty;
}

/// Provisions team-scope plugin bundles under
/// `config-profiles/teams/<teamId>/flashskyai/plugins/<manifest-name>/`.
///
/// Each entry is a symlink (or copy fallback) to the app-level plugin root.
class TeamPluginLinkerService {
  TeamPluginLinkerService({String? appPluginsRoot, StorageRoots? storageRoots})
    : _appPluginsRoot = appPluginsRoot,
      _storageRoots = storageRoots;

  final String? _appPluginsRoot;
  final StorageRoots? _storageRoots;

  String get appPluginsDir {
    final root = _appPluginsRoot;
    if (root != null) return root;
    throw StateError(
      'TeamPluginLinkerService requires appPluginsRoot or storageRoots.',
    );
  }

  String sourceDirFor(Plugin plugin) =>
      AppStorage.fs.pathContext.join(appPluginsDir, plugin.directory);

  Future<TeamPluginSyncResult> syncForTeam({
    required String teamId,
    required List<String> pluginIds,
    required List<Plugin> installed,
  }) async {
    final trimmedTeamId = teamId.trim();
    if (trimmedTeamId.isEmpty) {
      return const TeamPluginSyncResult();
    }

    final byId = {for (final p in installed) p.id: p};
    final toLink = <Plugin>[];
    final skipped = <String>[];
    for (final id in pluginIds) {
      final plugin = byId[id];
      if (plugin == null) {
        skipped.add(id);
        continue;
      }
      toLink.add(plugin);
    }

    final roots = await _storageRoots?.resolve();
    final fs = roots?.fs ?? AppStorage.fs;
    final layout =
        roots?.layout ??
        RuntimeLayout(teampilotRoot: _appPluginsRootParent(), fs: fs);
    final teamPluginsDir = layout.teamPluginsDir(trimmedTeamId);
    final sourceRoot = roots?.pluginsRoot ?? appPluginsDir;
    return _syncWithFilesystem(
      fs: fs,
      sourceRoot: sourceRoot,
      teamPluginsDir: teamPluginsDir,
      toLink: toLink,
      skipped: skipped,
    );
  }

  String _appPluginsRootParent() {
    final root = _appPluginsRoot;
    if (root == null || root.isEmpty) return '';
    return AppPaths.teampilotRootFromInstalledScopeDir(root);
  }

  Future<TeamPluginSyncResult> _syncWithFilesystem({
    required Filesystem fs,
    required String sourceRoot,
    required String teamPluginsDir,
    required List<Plugin> toLink,
    required List<String> skipped,
  }) async {
    final path = fs.pathContext;
    final errors = <String>[];
    final linked = <String>[];
    final resolutions = <(String, String)>[];
    final usedNames = <String>{};

    try {
      await fs.ensureDir(teamPluginsDir);
      for (final entry in await fs.listDir(teamPluginsDir)) {
        await fs.removeRecursive(path.join(teamPluginsDir, entry.name));
      }
    } catch (e) {
      return TeamPluginSyncResult(
        skippedMissingIds: skipped,
        errors: ['Failed to clear team plugins dir: $e'],
      );
    }

    for (final plugin in toLink) {
      final rawSource = path.join(sourceRoot, plugin.directory);
      try {
        if (!(await fs.stat(rawSource)).isDirectory) {
          errors.add('${plugin.name}: source missing at $rawSource');
          continue;
        }
        const paths = flashskyaiPluginManifestPaths;
        final pluginRoot = await CliPluginLayout.resolvePluginRoot(
          fs,
          rawSource,
          paths: paths,
        );
        if (pluginRoot == null) {
          errors.add(
            '${plugin.name}: no plugin manifest under $rawSource '
            '(expected ${paths.manifestRelativePath})',
          );
          continue;
        }
        var targetName = await CliPluginLayout.bundleDirName(
          fs,
          pluginRoot,
          paths: paths,
        );
        if (usedNames.contains(targetName)) {
          final owner = plugin.marketplaceOwner ?? 'local';
          final fallback = '${owner}__$targetName';
          resolutions.add((plugin.id, fallback));
          targetName = fallback;
        }
        usedNames.add(targetName);

        final target = path.join(teamPluginsDir, targetName);
        await CliPluginLayout.linkOrCopyTree(
          fs: fs,
          source: pluginRoot,
          destination: target,
        );
        await CliPluginLayout.normalizeBundleForFlavor(fs, target, paths);
        linked.add(targetName);
      } catch (e) {
        errors.add('${plugin.name}: $e');
        appLogger.w('[team-plugins] link failed for ${plugin.id}: $e');
      }
    }

    return TeamPluginSyncResult(
      linked: linked,
      skippedMissingIds: skipped,
      errors: errors,
      conflictResolutions: resolutions,
    );
  }
}
