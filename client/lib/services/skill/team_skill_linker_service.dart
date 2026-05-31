
import '../../models/skill.dart';
import '../../utils/logger.dart';
import '../cli/cli_data_layout.dart';
import '../storage/app_storage.dart';
import '../storage/flashskyai_storage_roots.dart';
import '../io/filesystem.dart';

class TeamSkillSyncResult {
  const TeamSkillSyncResult({
    this.linked = const [],
    this.skippedMissingIds = const [],
    this.errors = const [],
  });

  final List<String> linked;
  final List<String> skippedMissingIds;
  final List<String> errors;

  bool get ok => errors.isEmpty;
}

/// Provisions team-scope skill links under
/// `config-profiles/teams/<teamId>/flashskyai/skills/<skill-dir>`.
///
/// Source of truth is the UI-owned skills directory ([appSkillsDir]); the team
/// dir holds symlinks (or copies on Windows / SFTP fallback) per the layout's
/// 3-layer inheritance contract.
class TeamSkillLinkerService {
  TeamSkillLinkerService({
    String? appSkillsRoot,
    String? teamSkillsRootOverride,
    bool? useWslSymlinks,
    FlashskyaiStorageRoots? storageRoots,
  }) : _appSkillsRoot = appSkillsRoot,
       _teamSkillsRootOverride = teamSkillsRootOverride,
       _storageRoots = storageRoots;

  final String? _appSkillsRoot;
  final String? _teamSkillsRootOverride;
  final FlashskyaiStorageRoots? _storageRoots;

  String get appSkillsDir {
    final root = _appSkillsRoot;
    if (root != null) return root;
    throw StateError(
      'TeamSkillLinkerService requires appSkillsRoot or storageRoots.',
    );
  }

  /// Team-scope skills dir for [teamId] under the resolved layout.
  String teamSkillsDirFor(String teamId, {required CliDataLayout layout}) {
    final override = _teamSkillsRootOverride;
    if (override != null) return override;
    return layout.teamSkillsDir(teamId);
  }

  String sourceDirFor(Skill skill) =>
      AppStorage.fs.pathContext.join(appSkillsDir, skill.directory);

  Future<TeamSkillSyncResult> syncForTeam({
    required String teamId,
    required List<String> skillIds,
    required List<Skill> installed,
  }) async {
    final trimmedTeamId = teamId.trim();
    if (trimmedTeamId.isEmpty) {
      return const TeamSkillSyncResult();
    }

    final byId = {for (final s in installed) s.id: s};
    final toLink = <Skill>[];
    final skipped = <String>[];
    for (final id in skillIds) {
      final skill = byId[id];
      if (skill == null) {
        skipped.add(id);
        continue;
      }
      toLink.add(skill);
    }

    final roots = await _storageRoots?.resolve();
    final fs = roots?.fs ?? AppStorage.fs;
    final layout =
        roots?.layout ??
        CliDataLayout(
          teampilotRoot: _teamSkillsRootOverride != null
              ? ''
              : _appSkillsRootParent(),
          fs: fs,
        );
    final teamSkillsDir = teamSkillsDirFor(trimmedTeamId, layout: layout);
    final sourceRoot = roots?.skillsRoot ?? appSkillsDir;
    return _syncWithFilesystem(
      fs: fs,
      sourceRoot: sourceRoot,
      teamSkillsDir: teamSkillsDir,
      toLink: toLink,
      skipped: skipped,
    );
  }

  String _appSkillsRootParent() {
    final root = _appSkillsRoot;
    if (root == null || root.isEmpty) return '';
    return AppPaths.teampilotRootFromInstalledScopeDir(root);
  }

  Future<TeamSkillSyncResult> _syncWithFilesystem({
    required Filesystem fs,
    required String sourceRoot,
    required String teamSkillsDir,
    required List<Skill> toLink,
    required List<String> skipped,
  }) async {
    final path = fs.pathContext;
    final errors = <String>[];
    final linked = <String>[];

    try {
      await fs.ensureDir(teamSkillsDir);
      for (final entry in await fs.listDir(teamSkillsDir)) {
        await fs.removeRecursive(path.join(teamSkillsDir, entry.name));
      }
    } catch (e) {
      return TeamSkillSyncResult(
        skippedMissingIds: skipped,
        errors: ['Failed to clear team skills dir: $e'],
      );
    }

    for (final skill in toLink) {
      final source = path.join(sourceRoot, skill.directory);
      final target = path.join(teamSkillsDir, skill.directory);
      try {
        if (!(await fs.stat(source)).isDirectory) {
          errors.add('${skill.name}: source missing at $source');
          continue;
        }
        final linkedOk = await fs.createSymlink(
          target: source,
          linkPath: target,
        );
        if (!linkedOk) {
          await fs.copyTree(source: source, destination: target);
        }
        linked.add(skill.directory);
      } catch (e) {
        errors.add('${skill.name}: $e');
        appLogger.w('[team-skills] link failed for ${skill.id}: $e');
      }
    }

    return TeamSkillSyncResult(
      linked: linked,
      skippedMissingIds: skipped,
      errors: errors,
    );
  }
}
