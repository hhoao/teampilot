import '../../models/app_session.dart';
import '../../models/git_worktree.dart';
import 'git_worktree_service.dart';

/// Options collected from [showWorktreeDeleteDialog].
class WorktreeDeleteOptions {
  const WorktreeDeleteOptions({
    required this.force,
    required this.deleteBranch,
    required this.deleteSessions,
  });

  final bool force;
  final bool deleteBranch;
  final bool deleteSessions;
}

/// Removes a git worktree and optionally its branch and in-group sessions.
/// Extracted from the sidebar so delete-cascade behavior is unit-testable.
Future<void> removeWorktreeWithSessions({
  required GitWorktreeService service,
  required String repoPath,
  required String worktreePath,
  required GitWorktree? worktree,
  required WorktreeDeleteOptions options,
  required List<AppSession> sessionsInGroup,
  required Future<void> Function(String sessionId) deleteSession,
}) async {
  await service.remove(
    repoPath,
    worktreePath,
    force: options.force,
    deleteBranch: options.deleteBranch ? worktree?.shortBranch : null,
  );
  if (options.deleteSessions) {
    for (final session in sessionsInGroup) {
      await deleteSession(session.sessionId);
    }
  }
}
