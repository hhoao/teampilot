// Local git working-tree state for the source control panel.
//
// Parsed from `git status --porcelain=v2 --branch` (see GitService.status).
// Desktop-local only (no SSH/WSL remote repos).

/// How a single path changed, mapped from porcelain XY status codes.
enum GitChangeKind { modified, added, deleted, renamed, untracked, conflicted }

/// One changed path, in either the index (staged) or worktree (unstaged) area.
class GitFileChange {
  const GitFileChange({
    required this.path,
    required this.kind,
    required this.staged,
    this.originalPath,
  });

  /// Path relative to the repository root.
  final String path;

  /// Previous path when [kind] is [GitChangeKind.renamed]; otherwise null.
  final String? originalPath;

  final GitChangeKind kind;

  /// True when this entry comes from the index (staged) area.
  final bool staged;

  /// Single-letter badge shown in the UI (M/A/D/R/U/?).
  String get badge => switch (kind) {
    GitChangeKind.modified => 'M',
    GitChangeKind.added => 'A',
    GitChangeKind.deleted => 'D',
    GitChangeKind.renamed => 'R',
    GitChangeKind.conflicted => 'U',
    GitChangeKind.untracked => '?',
  };
}

/// Snapshot of a repository's branch and pending changes.
class GitRepoStatus {
  const GitRepoStatus({
    required this.isRepository,
    this.branch,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
    this.staged = const [],
    this.unstaged = const [],
  });

  /// Sentinel for a directory that is not inside a git work tree.
  static const GitRepoStatus notARepository = GitRepoStatus(
    isRepository: false,
  );

  final bool isRepository;

  /// Current branch name, or null when detached HEAD.
  final String? branch;
  final String? upstream;
  final int ahead;
  final int behind;

  /// Index-area changes (ready to commit).
  final List<GitFileChange> staged;

  /// Worktree-area changes, including untracked files.
  final List<GitFileChange> unstaged;

  bool get hasChanges => staged.isNotEmpty || unstaged.isNotEmpty;
}
