import '../../models/plugin.dart';
import '../../utils/logger.dart';
import '../storage/app_storage.dart';
import '../cli/cli_data_layout.dart';
import 'cli_plugin_layout.dart';
import '../cli/registry/capabilities/plugin_manifest_capability.dart';
import '../storage/storage_resolver.dart';
import '../io/filesystem.dart';
import 'team_plugin_linker_service.dart';

/// Provisions personal-project plugin bundles under
/// `config-profiles/standalone/projects/<projectId>/flashskyai/plugins/<manifest-name>/`.
///
/// Each entry is a symlink (or copy fallback) to the app-level plugin root.
class ProjectPluginLinkerService {
  ProjectPluginLinkerService({
    String? appPluginsRoot,
    StorageRoots? storageRoots,
  }) : _appPluginsRoot = appPluginsRoot,
       _storageRoots = storageRoots;

  final String? _appPluginsRoot;
  final StorageRoots? _storageRoots;

  String get appPluginsDir {
    final root = _appPluginsRoot;
    if (root != null) return root;
    throw StateError(
      'ProjectPluginLinkerService requires appPluginsRoot or storageRoots.',
    );
  }

  String sourceDirFor(Plugin plugin) =>
      AppStorage.fs.pathContext.join(appPluginsDir, plugin.directory);

  Future<TeamPluginSyncResult> syncForProject({
    required String projectId,
    required List<String> pluginIds,
    required List<Plugin> installed,
  }) async {
    final trimmedProjectId = projectId.trim();
    if (trimmedProjectId.isEmpty) {
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
        CliDataLayout(teampilotRoot: _appPluginsRootParent(), fs: fs);
    final projectPluginsDir = layout.standaloneProjectPluginsDir(trimmedProjectId);
    final sourceRoot = roots?.pluginsRoot ?? appPluginsDir;
    return _syncWithFilesystem(
      fs: fs,
      sourceRoot: sourceRoot,
      projectPluginsDir: projectPluginsDir,
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
    required String projectPluginsDir,
    required List<Plugin> toLink,
    required List<String> skipped,
  }) async {
    final path = fs.pathContext;
    final errors = <String>[];
    final linked = <String>[];
    final resolutions = <(String, String)>[];
    final usedNames = <String>{};

    try {
      await fs.ensureDir(projectPluginsDir);
      for (final entry in await fs.listDir(projectPluginsDir)) {
        await fs.removeRecursive(path.join(projectPluginsDir, entry.name));
      }
    } catch (e) {
      return TeamPluginSyncResult(
        skippedMissingIds: skipped,
        errors: ['Failed to clear project plugins dir: $e'],
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

        final target = path.join(projectPluginsDir, targetName);
        await CliPluginLayout.linkOrCopyTree(
          fs: fs,
          source: pluginRoot,
          destination: target,
        );
        await CliPluginLayout.normalizeBundleForFlavor(fs, target, paths);
        linked.add(targetName);
      } catch (e) {
        errors.add('${plugin.name}: $e');
        appLogger.w('[project-plugins] link failed for ${plugin.id}: $e');
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
