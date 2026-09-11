import '../../models/app_session.dart';
import '../../models/git_worktree.dart';
import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import 'session_worktree_grouping.dart';
import '../workspace/workspace_path_utils.dart';

bool sessionBelongsToProject(
  AppSession session,
  String projectPath, {
  required bool usesPosixPaths,
}) {
  final primary = normalizeWorkspacePath(
    session.firstFolderPath,
    usesPosixPaths: usesPosixPaths,
  );
  final root = normalizeWorkspacePath(
    projectPath,
    usesPosixPaths: usesPosixPaths,
  );
  if (primary.isEmpty || root.isEmpty) return false;
  if (workspacePathsEqual(primary, root, usesPosixPaths: usesPosixPaths)) {
    return true;
  }
  return primary.startsWith(root.endsWith('/') ? root : '$root/');
}

/// The workspace folder that owns [session].
///
/// Git-backed projects ([worktreesByProjectPath] entry non-empty): the repo
/// whose `git worktree list` contains [session.firstFolderPath]. Plain folders
/// (no worktrees): longest workspace-folder path prefix match.
String? owningProjectFolderForSession(
  AppSession session,
  List<WorkspaceFolder> folders, {
  required bool usesPosixPaths,
  Map<String, List<GitWorktree>>? worktreesByProjectPath,
}) {
  final primary = normalizeWorkspacePath(
    session.firstFolderPath,
    usesPosixPaths: usesPosixPaths,
  );
  if (primary.isEmpty) return null;

  if (worktreesByProjectPath != null) {
    String? bestWorktreeOwner;
    var bestWorktreeLen = -1;
    for (final folder in folders) {
      final worktrees = worktreesByProjectPath[folder.path] ?? const [];
      if (worktrees.isEmpty) continue;
      final matched = worktreePathForSessionPath(
        primary,
        worktrees,
        usesPosixPaths: usesPosixPaths,
      );
      if (matched == null) continue;
      final matchedLen = normalizeWorkspacePath(
        matched,
        usesPosixPaths: usesPosixPaths,
      ).length;
      if (matchedLen > bestWorktreeLen) {
        bestWorktreeOwner = folder.path;
        bestWorktreeLen = matchedLen;
      }
    }
    if (bestWorktreeOwner != null) return bestWorktreeOwner;
  }

  String? bestPath;
  var bestLen = -1;
  for (final folder in folders) {
    final root = normalizeWorkspacePath(
      folder.path,
      usesPosixPaths: usesPosixPaths,
    );
    if (root.isEmpty ||
        !sessionBelongsToProject(
          session,
          folder.path,
          usesPosixPaths: usesPosixPaths,
        )) {
      continue;
    }
    if (root.length > bestLen) {
      bestPath = folder.path;
      bestLen = root.length;
    }
  }
  return bestPath;
}

Map<String, List<AppSession>> _sessionsByOwningProjectFolder({
  required List<WorkspaceFolder> folders,
  required Map<String, List<GitWorktree>> worktreesByProjectPath,
  required List<AppSession> sessions,
  required bool usesPosixPaths,
}) {
  final buckets = <String, List<AppSession>>{};
  for (final session in sessions) {
    final owner = owningProjectFolderForSession(
      session,
      folders,
      usesPosixPaths: usesPosixPaths,
      worktreesByProjectPath: worktreesByProjectPath,
    );
    if (owner == null) continue;
    final key = _folderBucketKey(folders, owner, usesPosixPaths: usesPosixPaths);
    if (key == null) continue;
    buckets.putIfAbsent(key, () => []).add(session);
  }
  return buckets;
}

String? _folderBucketKey(
  List<WorkspaceFolder> folders,
  String ownerPath, {
  required bool usesPosixPaths,
}) {
  final normalizedOwner = normalizeWorkspacePath(
    ownerPath,
    usesPosixPaths: usesPosixPaths,
  );
  for (final folder in folders) {
    if (workspacePathsEqual(
      folder.path,
      normalizedOwner,
      usesPosixPaths: usesPosixPaths,
    )) {
      return folder.path;
    }
  }
  return null;
}

/// Flat worktree → session buckets across every workspace folder (project).
///
/// Non-git folders become a single project group; git repos bucket by worktree.
/// When branch names collide across projects the label becomes `projectName/branch`.
List<WorktreeGroup> groupSessionsByWorktreeAcrossProjects({
  required List<WorkspaceFolder> folders,
  required Map<String, List<GitWorktree>> worktreesByProjectPath,
  required List<AppSession> sessions,
  required bool usesPosixPaths,
}) {
  final groups = <WorktreeGroup>[];
  final orphanSessions = <AppSession>[];
  final sessionsByFolder = _sessionsByOwningProjectFolder(
    folders: folders,
    worktreesByProjectPath: worktreesByProjectPath,
    sessions: sessions,
    usesPosixPaths: usesPosixPaths,
  );
  final assigned = sessionsByFolder.values
      .expand((list) => list.map((s) => s.sessionId))
      .toSet();

  for (final folder in folders) {
    final projectSessions = sessionsByFolder[folder.path] ?? const [];
    final worktrees = worktreesByProjectPath[folder.path] ?? const [];
    if (worktrees.isEmpty) {
      groups.add(
        WorktreeGroup(
          worktree: null,
          sessions: projectSessions,
          projectFolderPath: folder.path,
          isProjectGroup: true,
        ),
      );
      continue;
    }
    for (final wtGroup in groupSessionsByWorktree(
      worktrees: worktrees,
      sessions: projectSessions,
      usesPosixPaths: usesPosixPaths,
    )) {
      if (wtGroup.isOrphan) {
        orphanSessions.addAll(wtGroup.sessions);
        continue;
      }
      groups.add(
        WorktreeGroup(
          worktree: wtGroup.worktree,
          sessions: wtGroup.sessions,
          projectFolderPath: folder.path,
        ),
      );
    }
  }

  for (final session in sessions) {
    if (!assigned.contains(session.sessionId)) {
      orphanSessions.add(session);
    }
  }
  if (orphanSessions.isNotEmpty) {
    groups.add(WorktreeGroup(worktree: null, sessions: orphanSessions));
  }

  return _withDisambiguatedSidebarLabels(groups);
}

/// Rebuilds [group]'s membership from an unfiltered session source.
///
/// This preserves the same project ownership and longest-worktree-prefix rules
/// used by [groupSessionsByWorktreeAcrossProjects].
List<AppSession> unfilteredSessionsForWorktreeGroup({
  required WorktreeGroup group,
  required List<WorkspaceFolder> folders,
  required Map<String, List<GitWorktree>> worktreesByProjectPath,
  required List<AppSession> sessions,
  required bool usesPosixPaths,
}) {
  final targetWorktree = group.worktree;
  if (targetWorktree == null) return const [];
  final targetProject = group.projectFolderPath?.trim() ?? '';
  final rebuilt = groupSessionsByWorktreeAcrossProjects(
    folders: folders,
    worktreesByProjectPath: worktreesByProjectPath,
    sessions: sessions,
    usesPosixPaths: usesPosixPaths,
  );
  for (final candidate in rebuilt) {
    final candidateWorktree = candidate.worktree;
    if (candidateWorktree == null ||
        !workspacePathsEqual(
          candidateWorktree.path,
          targetWorktree.path,
          usesPosixPaths: usesPosixPaths,
        )) {
      continue;
    }
    if (targetProject.isNotEmpty &&
        !workspacePathsEqual(
          candidate.projectFolderPath ?? '',
          targetProject,
          usesPosixPaths: usesPosixPaths,
        )) {
      continue;
    }
    return candidate.sessions;
  }
  return const [];
}

List<WorktreeGroup> _withDisambiguatedSidebarLabels(List<WorktreeGroup> groups) {
  final branchCounts = <String, int>{};
  for (final group in groups) {
    final wt = group.worktree;
    if (wt == null || group.isProjectGroup) continue;
    final branch = wt.shortBranch;
    branchCounts[branch] = (branchCounts[branch] ?? 0) + 1;
  }

  return [
    for (final group in groups)
      if (group.worktree != null &&
          !group.isProjectGroup &&
          (branchCounts[group.worktree!.shortBranch] ?? 0) > 1 &&
          group.projectFolderPath?.trim().isNotEmpty == true)
        WorktreeGroup(
          worktree: group.worktree,
          sessions: group.sessions,
          projectFolderPath: group.projectFolderPath,
          sidebarLabel:
              '${Workspace.directoryName(group.projectFolderPath!)}/${group.worktree!.shortBranch}',
        )
      else
        group,
  ];
}
