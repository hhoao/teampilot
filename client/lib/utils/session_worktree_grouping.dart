import '../models/app_session.dart';
import '../models/git_worktree.dart';
import 'workspace_path_utils.dart';

/// One sidebar group: a worktree (null == orphan/"other") + its sessions.
class WorktreeGroup {
  const WorktreeGroup({required this.worktree, required this.sessions});
  final GitWorktree? worktree;
  final List<AppSession> sessions;
  bool get isOrphan => worktree == null;
}

/// Bucket [sessions] under the worktree whose normalized path is the longest
/// prefix of the session's primaryPath. Unmatched sessions go to a trailing
/// orphan group (only present when non-empty). Main worktree group is first;
/// empty worktree groups are kept so the sidebar can offer "new conversation".
List<WorktreeGroup> groupSessionsByWorktree({
  required List<GitWorktree> worktrees,
  required List<AppSession> sessions,
}) {
  final ordered = [...worktrees]..sort((a, b) {
      if (a.isMainWorktree != b.isMainWorktree) return a.isMainWorktree ? -1 : 1;
      return a.shortBranch.compareTo(b.shortBranch);
    });
  final buckets = {for (final w in ordered) w.path: <AppSession>[]};
  final orphans = <AppSession>[];

  for (final session in sessions) {
    final sessionPath = normalizeWorkspacePath(session.primaryPath);
    String? bestPath;
    var bestLen = -1;
    for (final w in ordered) {
      final wPath = normalizeWorkspacePath(w.path);
      if (_isUnderOrEqual(sessionPath, wPath) && wPath.length > bestLen) {
        bestPath = w.path;
        bestLen = wPath.length;
      }
    }
    if (bestPath == null) {
      orphans.add(session);
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

bool _isUnderOrEqual(String child, String parent) {
  if (child == parent) return true;
  return child.startsWith(parent.endsWith('/') ? parent : '$parent/');
}
