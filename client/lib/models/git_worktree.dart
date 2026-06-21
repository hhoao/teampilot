/// One git worktree as reported by `git worktree list --porcelain`.
/// Path-derived identity — not persisted; re-read from git each time.
class GitWorktree {
  const GitWorktree({
    required this.path,
    required this.branch,
    required this.head,
    required this.isBare,
    required this.isMainWorktree,
  });

  /// Absolute worktree path (normalize before comparing).
  final String path;

  /// `refs/heads/...`, or empty for a detached HEAD.
  final String branch;

  /// Commit oid the worktree HEAD points at.
  final String head;

  final bool isBare;

  /// True for the repo's main working tree (first `git worktree list` entry).
  final bool isMainWorktree;

  bool get isDetached => branch.isEmpty;

  /// Branch without the `refs/heads/` prefix; short oid when detached.
  String get shortBranch {
    if (branch.isEmpty) {
      return head.length > 7 ? head.substring(0, 7) : head;
    }
    const prefix = 'refs/heads/';
    return branch.startsWith(prefix) ? branch.substring(prefix.length) : branch;
  }
}
