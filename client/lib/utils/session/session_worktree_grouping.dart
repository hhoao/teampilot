import '../../models/app_session.dart';
import '../../models/git_worktree.dart';
import '../workspace/workspace_path_utils.dart';

/// One sidebar group: a git worktree, a non-git project folder, or orphans.
class WorktreeGroup {
  const WorktreeGroup({
    required this.worktree,
    required this.sessions,
    this.projectFolderPath,
    this.sidebarLabel,
    this.isProjectGroup = false,
  });

  final GitWorktree? worktree;
  final List<AppSession> sessions;

  /// Workspace folder (git project) that owns [worktree], when known.
  final String? projectFolderPath;

  /// Optional disambiguated label (e.g. `project/main` when branch names collide).
  final String? sidebarLabel;

  /// True when [worktree] is absent because the folder is not a git repo.
  final bool isProjectGroup;

  bool get isOrphan => worktree == null && !isProjectGroup;
}

/// Bucket [sessions] under the worktree whose normalized path is the longest
/// prefix of the first matching session folder. Unmatched sessions go to a
/// trailing orphan group (only present when non-empty). Main worktree group is
/// first; empty worktree groups are kept so the sidebar can offer "new
/// conversation".
List<WorktreeGroup> groupSessionsByWorktree({
  required List<GitWorktree> worktrees,
  required List<AppSession> sessions,
  required bool usesPosixPaths,
}) {
  final ordered = [...worktrees]
    ..sort((a, b) {
      if (a.isMainWorktree != b.isMainWorktree) {
        return a.isMainWorktree ? -1 : 1;
      }
      return a.shortBranch.compareTo(b.shortBranch);
    });
  final buckets = {for (final w in ordered) w.path: <AppSession>[]};
  final orphans = <AppSession>[];

  for (final session in sessions) {
    final bestPath = _worktreePathForSession(
      session,
      ordered,
      usesPosixPaths: usesPosixPaths,
    );
    if (bestPath == null) {
      if (_hasNoFolderMetadata(session) && ordered.isNotEmpty) {
        final main = ordered.firstWhere(
          (worktree) => worktree.isMainWorktree,
          orElse: () => ordered.first,
        );
        buckets[main.path]!.add(session);
      } else {
        orphans.add(session);
      }
    } else {
      buckets[bestPath]!.add(session);
    }
  }

  final groups = [
    for (final w in ordered)
      WorktreeGroup(worktree: w, sessions: buckets[w.path]!),
  ];
  if (orphans.isNotEmpty) {
    groups.add(WorktreeGroup(worktree: null, sessions: orphans));
  }
  return groups;
}

String? _worktreePathForSession(
  AppSession session,
  List<GitWorktree> worktrees, {
  required bool usesPosixPaths,
}) {
  for (final folder in session.folders) {
    final path = folder.path.trim();
    if (path.isEmpty) continue;
    final matched = worktreePathForSessionPath(
      path,
      worktrees,
      usesPosixPaths: usesPosixPaths,
    );
    if (matched != null) return matched;
  }
  return null;
}

bool _hasNoFolderMetadata(AppSession session) =>
    session.folders.every((folder) => folder.path.trim().isEmpty);

/// Returns the worktree whose normalized path is the longest prefix of
/// [sessionPrimaryPath], or null when no worktree contains the path.
String? worktreePathForSessionPath(
  String sessionPrimaryPath,
  List<GitWorktree> worktrees, {
  required bool usesPosixPaths,
}) {
  final sessionPath = normalizeWorkspacePath(
    sessionPrimaryPath,
    usesPosixPaths: usesPosixPaths,
  );
  String? bestPath;
  var bestLen = -1;
  for (final w in worktrees) {
    final wPath = normalizeWorkspacePath(
      w.path,
      usesPosixPaths: usesPosixPaths,
    );
    if (_isUnderOrEqual(sessionPath, wPath) && wPath.length > bestLen) {
      bestPath = w.path;
      bestLen = wPath.length;
    }
  }
  return bestPath;
}

bool _isUnderOrEqual(String child, String parent) {
  if (child == parent) return true;
  return child.startsWith(parent.endsWith('/') ? parent : '$parent/');
}
