/// A local or remote-only branch choice for the worktree-create dialog.
class WorktreeBranchOption {
  const WorktreeBranchOption.local(this.name) : remoteRef = null;

  const WorktreeBranchOption.fromRemote({
    required this.name,
    required this.remoteRef,
  });

  /// Local branch name used for the worktree path and `git worktree add`.
  final String name;

  /// Remote tracking ref (e.g. `origin/feature/x`) when no local branch exists.
  final String? remoteRef;

  bool get isLocal => remoteRef == null;

  bool get isRemoteOnly => remoteRef != null;

  String get displayLabel => remoteRef ?? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorktreeBranchOption &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          remoteRef == other.remoteRef;

  @override
  int get hashCode => Object.hash(name, remoteRef);
}

/// Local branches first, then remote-only refs without a matching local name.
List<WorktreeBranchOption> mergeWorktreeBranchOptions({
  required List<String> local,
  required List<String> remote,
}) {
  final localSet = local.map((b) => b.trim()).where((b) => b.isNotEmpty).toSet();
  final options = <WorktreeBranchOption>[
    for (final name in local)
      if (name.trim().isNotEmpty) WorktreeBranchOption.local(name.trim()),
  ];
  for (final ref in remote) {
    final trimmed = ref.trim();
    if (trimmed.isEmpty || trimmed.endsWith('/HEAD')) continue;
    final slash = trimmed.indexOf('/');
    if (slash < 0 || slash == trimmed.length - 1) continue;
    final localName = trimmed.substring(slash + 1);
    if (localSet.contains(localName)) continue;
    options.add(
      WorktreeBranchOption.fromRemote(name: localName, remoteRef: trimmed),
    );
  }
  return options;
}

/// Suggest a new worktree branch name from the repo's current/default branch.
String suggestWorktreeBranchName(String? currentBranch) {
  final base = (currentBranch ?? '').trim();
  if (base.isEmpty) return 'worktree';
  return '$base-wt';
}
