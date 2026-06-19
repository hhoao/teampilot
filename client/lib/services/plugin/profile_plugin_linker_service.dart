import '../../models/plugin.dart';
import '../../utils/logger.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_layout.dart';
import 'cli_plugin_layout.dart';
import '../cli/registry/capabilities/plugin_manifest_paths.dart';
import '../cli/registry/capabilities/plugin_provisioner_capability.dart';
import '../storage/storage_resolver.dart';
import '../io/filesystem.dart';

class ProfilePluginSyncResult {
  const ProfilePluginSyncResult({
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

/// Provisions identity-scope plugin bundles under
/// `identities-runtime/<profileId>/flashskyai/plugins/<manifest-name>/`.
///
/// Each entry is a symlink (or copy fallback) to the app-level plugin root.
class ProfilePluginLinkerService {
  ProfilePluginLinkerService({String? appPluginsRoot, StorageRoots? storageRoots})
    : _appPluginsRoot = appPluginsRoot,
      _storageRoots = storageRoots;

  final String? _appPluginsRoot;
  final StorageRoots? _storageRoots;

  String get appPluginsDir {
    final root = _appPluginsRoot;
    if (root != null) return root;
    throw StateError(
      'ProfilePluginLinkerService requires appPluginsRoot or storageRoots.',
    );
  }

  String sourceDirFor(Plugin plugin) =>
      AppStorage.fs.pathContext.join(appPluginsDir, plugin.directory);

  Future<ProfilePluginSyncResult> syncForProfile({
    required String profileId,
    required List<String> pluginIds,
    required List<Plugin> installed,
  }) async {
    final trimmedIdentityId = profileId.trim();
    if (trimmedIdentityId.isEmpty) {
      return const ProfilePluginSyncResult();
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
    final identityPluginsDir = layout.identityPluginsDir(trimmedIdentityId);
    final sourceRoot = roots?.pluginsRoot ?? appPluginsDir;
    return _syncWithFilesystem(
      fs: fs,
      sourceRoot: sourceRoot,
      identityPluginsDir: identityPluginsDir,
      toLink: toLink,
      skipped: skipped,
    );
  }

  String _appPluginsRootParent() {
    final root = _appPluginsRoot;
    if (root == null || root.isEmpty) return '';
    return AppPaths.teampilotRootFromInstalledScopeDir(root);
  }

  Future<ProfilePluginSyncResult> _syncWithFilesystem({
    required Filesystem fs,
    required String sourceRoot,
    required String identityPluginsDir,
    required List<Plugin> toLink,
    required List<String> skipped,
  }) async {
    final path = fs.pathContext;
    final errors = <String>[];
    final linked = <String>[];
    final resolutions = <(String, String)>[];
    final usedNames = <String>{};

    try {
      await fs.ensureDir(identityPluginsDir);
      for (final entry in await fs.listDir(identityPluginsDir)) {
        await fs.removeRecursive(path.join(identityPluginsDir, entry.name));
      }
    } catch (e) {
      return ProfilePluginSyncResult(
        skippedMissingIds: skipped,
        errors: ['Failed to clear identity plugins dir: $e'],
      );
    }

    for (final plugin in toLink) {
      final rawSource = path.join(sourceRoot, plugin.directory);
      try {
        if (!(await fs.stat(rawSource)).isDirectory) {
          errors.add('${plugin.name}: source missing at $rawSource');
          continue;
        }
        const paths = neutralPluginManifestPaths;
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

        final target = path.join(identityPluginsDir, targetName);
        await CliPluginLayout.linkOrCopyTree(
          fs: fs,
          source: pluginRoot,
          destination: target,
        );
        await CliPluginLayout.projectBundleToFlavor(
          fs,
          target,
          flashskyaiPluginManifestPaths,
        );
        linked.add(targetName);
      } catch (e) {
        errors.add('${plugin.name}: $e');
        appLogger.w('[identity-plugins] link failed for ${plugin.id}: $e');
      }
    }

    return ProfilePluginSyncResult(
      linked: linked,
      skippedMissingIds: skipped,
      errors: errors,
      conflictResolutions: resolutions,
    );
  }
}
