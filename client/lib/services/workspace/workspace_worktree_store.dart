import '../../models/git_worktree.dart';

/// Cached git worktree list for one workspace repo path.
class WorkspaceWorktreeSnapshot {
  const WorkspaceWorktreeSnapshot({
    required this.repoPath,
    required this.worktrees,
  });

  final String repoPath;
  final List<GitWorktree> worktrees;
}

/// App-level cache of `git worktree list` results, keyed by workspace + repo.
///
/// Mirrors [WorkspaceFileTreeStore]: switching workspace tabs disposes the
/// widget subtree but the last-known worktree list is retained so the sidebar
/// can render grouped sessions immediately on return.
class WorkspaceWorktreeStore {
  final Map<String, WorkspaceWorktreeSnapshot> _snapshots =
      <String, WorkspaceWorktreeSnapshot>{};

  static String _key(String workspaceId, String repoPath) =>
      '${workspaceId.trim()}@${repoPath.trim()}';

  WorkspaceWorktreeSnapshot? peek(String workspaceId, String repoPath) {
    final key = _key(workspaceId, repoPath);
    if (key == '@') return null;
    return _snapshots[key];
  }

  void remember(
    String workspaceId,
    String repoPath,
    List<GitWorktree> worktrees,
  ) {
    final ws = workspaceId.trim();
    final repo = repoPath.trim();
    if (ws.isEmpty || repo.isEmpty) return;
    _snapshots[_key(ws, repo)] = WorkspaceWorktreeSnapshot(
      repoPath: repo,
      worktrees: List<GitWorktree>.unmodifiable(worktrees),
    );
  }

  /// Drops all cached lists for [workspaceId] when its editor tab is closed.
  void removeWorkspace(String workspaceId) {
    final prefix = '${workspaceId.trim()}@';
    if (prefix == '@') return;
    _snapshots.removeWhere((key, _) => key.startsWith(prefix));
  }

  void dispose() => _snapshots.clear();
}
