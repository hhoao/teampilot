import '../../models/skill.dart';
import '../../utils/logger.dart';
import '../cli/cli_data_layout.dart';
import '../storage/app_storage.dart';
import '../storage/storage_resolver.dart';
import '../io/filesystem.dart';
import 'team_skill_linker_service.dart';

/// Provisions personal-project skill links under
/// `config-profiles/standalone/projects/<projectId>/flashskyai/skills/<skill-dir>`.
///
/// Source of truth is the UI-owned skills directory ([appSkillsDir]); the
/// project dir holds symlinks (or copies on Windows / SFTP fallback).
class ProjectSkillLinkerService {
  ProjectSkillLinkerService({
    String? appSkillsRoot,
    String? projectSkillsRootOverride,
    StorageRoots? storageRoots,
  }) : _appSkillsRoot = appSkillsRoot,
       _projectSkillsRootOverride = projectSkillsRootOverride,
       _storageRoots = storageRoots;

  final String? _appSkillsRoot;
  final String? _projectSkillsRootOverride;
  final StorageRoots? _storageRoots;

  String get appSkillsDir {
    final root = _appSkillsRoot;
    if (root != null) return root;
    throw StateError(
      'ProjectSkillLinkerService requires appSkillsRoot or storageRoots.',
    );
  }

  /// Project-scope skills dir for [projectId] under the resolved layout.
  String projectSkillsDirFor(
    String projectId, {
    required CliDataLayout layout,
  }) {
    final override = _projectSkillsRootOverride;
    if (override != null) return override;
    return layout.standaloneProjectSkillsDir(projectId);
  }

  String sourceDirFor(Skill skill) =>
      AppStorage.fs.pathContext.join(appSkillsDir, skill.directory);

  Future<TeamSkillSyncResult> syncForProject({
    required String projectId,
    required List<String> skillIds,
    required List<Skill> installed,
  }) async {
    final trimmedProjectId = projectId.trim();
    if (trimmedProjectId.isEmpty) {
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
          teampilotRoot: _projectSkillsRootOverride != null
              ? ''
              : _appSkillsRootParent(),
          fs: fs,
        );
    final projectSkillsDir = projectSkillsDirFor(
      trimmedProjectId,
      layout: layout,
    );
    final sourceRoot = roots?.skillsRoot ?? appSkillsDir;
    return _syncWithFilesystem(
      fs: fs,
      sourceRoot: sourceRoot,
      projectSkillsDir: projectSkillsDir,
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
    required String projectSkillsDir,
    required List<Skill> toLink,
    required List<String> skipped,
  }) async {
    final path = fs.pathContext;
    final errors = <String>[];
    final linked = <String>[];

    try {
      await fs.ensureDir(projectSkillsDir);
      for (final entry in await fs.listDir(projectSkillsDir)) {
        await fs.removeRecursive(path.join(projectSkillsDir, entry.name));
      }
    } catch (e) {
      return TeamSkillSyncResult(
        skippedMissingIds: skipped,
        errors: ['Failed to clear project skills dir: $e'],
      );
    }

    for (final skill in toLink) {
      final source = path.join(sourceRoot, skill.directory);
      final target = path.join(projectSkillsDir, skill.directory);
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
        appLogger.w('[project-skills] link failed for ${skill.id}: $e');
      }
    }

    return TeamSkillSyncResult(
      linked: linked,
      skippedMissingIds: skipped,
      errors: errors,
    );
  }
}
