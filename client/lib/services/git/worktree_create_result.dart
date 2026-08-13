import 'worktree_branch_options.dart';

/// Result of [buildWorktreeCreateResult]; the dialog pops it on create.
class WorktreeCreateResult {
  const WorktreeCreateResult({
    required this.worktreePath,
    required this.branch,
    required this.baseRef,
    required this.existingBranch,
  });

  /// Absolute path where the worktree will be created.
  final String worktreePath;

  /// Branch name: checked out when [existingBranch], else created new.
  final String branch;

  /// Base ref for a new branch; null/empty means current HEAD.
  final String? baseRef;

  /// True → check out [branch]; false → create a new branch from [baseRef].
  final bool existingBranch;
}

/// Maps the dialog's free-form inputs to `git worktree add` semantics:
/// - Empty selector → derive [branch] from current HEAD.
/// - Selector text matching a local branch X → check out X when
///   [branch] == X, otherwise derive [branch] from X.
/// - Selector text matching a remote-only branch (displayed as `origin/x`) →
///   derive [branch] from `origin/x`.
/// - Any other selector text → treat as a custom ref and derive from it.
WorktreeCreateResult buildWorktreeCreateResult({
  required String branch,
  required String selectorText,
  required List<WorktreeBranchOption> options,
  required String worktreePath,
}) {
  final trimmedBranch = branch.trim();
  if (trimmedBranch.isEmpty) {
    throw ArgumentError.value(branch, 'branch', 'must not be empty');
  }
  final trimmedSelector = selectorText.trim();
  final option = worktreeOptionForLabel(options, trimmedSelector);
  if (option != null) {
    if (option.isLocal && trimmedBranch == option.name) {
      return WorktreeCreateResult(
        worktreePath: worktreePath,
        branch: option.name,
        baseRef: null,
        existingBranch: true,
      );
    }
    return WorktreeCreateResult(
      worktreePath: worktreePath,
      branch: trimmedBranch,
      baseRef: option.remoteRef ?? option.name,
      existingBranch: false,
    );
  }
  return WorktreeCreateResult(
    worktreePath: worktreePath,
    branch: trimmedBranch,
    baseRef: trimmedSelector.isEmpty ? null : trimmedSelector,
    existingBranch: false,
  );
}

/// Option whose [WorktreeBranchOption.displayLabel] equals [label], else null.
WorktreeBranchOption? worktreeOptionForLabel(
  List<WorktreeBranchOption> options,
  String label,
) {
  if (label.isEmpty) return null;
  for (final option in options) {
    if (option.displayLabel == label) return option;
  }
  return null;
}
