import '../models/plugin.dart';
import '../utils/logger.dart';
import 'app_storage.dart';
import 'cli_data_layout.dart';
import 'flashskyai_storage_roots.dart';
import 'io/filesystem.dart';

class TeamPluginSyncResult {
  const TeamPluginSyncResult({
    this.linked = const [],
    this.skippedMissingIds = const [],
    this.errors = const [],
  });

  final List<String> linked;
  final List<String> skippedMissingIds;
  final List<String> errors;

  bool get ok => errors.isEmpty;
}

/// Provisions team-scope plugin links under
/// `config-profiles/teams/<teamId>/flashskyai/plugins/<plugin-dir>`.
///
/// Mirrors [TeamSkillLinkerService] for plugins. Source plugins live under
/// [appPluginsDir]; each enabled plugin is linked (or copied on Windows/SFTP)
/// into the team's CLI layout.
class TeamPluginLinkerService {
  TeamPluginLinkerService({
    String? appPluginsRoot,
    FlashskyaiStorageRoots? storageRoots,
  })  : _appPluginsRoot = appPluginsRoot,
        _storageRoots = storageRoots;

  final String? _appPluginsRoot;
  final FlashskyaiStorageRoots? _storageRoots;

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
    final layout = roots?.layout ??
        CliDataLayout(
          teampilotRoot: _appPluginsRootParent(),
          fs: fs,
        );
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
    final ctx = AppStorage.fs.pathContext;
    return ctx.dirname(root);
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
      final source = path.join(sourceRoot, plugin.directory);
      final target = path.join(teamPluginsDir, plugin.directory);
      try {
        if (!(await fs.stat(source)).isDirectory) {
          errors.add('${plugin.name}: source missing at $source');
          continue;
        }
        final linkedOk = await fs.createSymlink(
          target: source,
          linkPath: target,
        );
        if (!linkedOk) {
          await fs.copyTree(source: source, destination: target);
        }
        linked.add(plugin.directory);
      } catch (e) {
        errors.add('${plugin.name}: $e');
        appLogger.w('[team-plugins] link failed for ${plugin.id}: $e');
      }
    }

    return TeamPluginSyncResult(
      linked: linked,
      skippedMissingIds: skipped,
      errors: errors,
    );
  }
}
