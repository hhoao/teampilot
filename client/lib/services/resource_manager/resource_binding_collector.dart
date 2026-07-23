import '../../models/git_worktree.dart';
import '../../utils/session/session_worktree_grouping.dart';
import 'resource_binding.dart';

/// Thin input for one chat member shell row (ChatCubit mapping is elsewhere).
class ChatMemberShellRef {
  const ChatMemberShellRef({
    required this.workspaceId,
    required this.sessionId,
    required this.memberId,
    required this.sessionTitle,
    required this.memberName,
    required this.sessionPrimaryPath,
    required this.connected,
    this.livePid,
  });

  final String workspaceId;
  final String sessionId;
  final String memberId;
  final String sessionTitle;
  final String memberName;
  final String sessionPrimaryPath;
  final bool connected;
  final int? livePid;
}

/// Thin input for one workspace bottom-shell tab row.
class WorkspaceShellRef {
  const WorkspaceShellRef({
    required this.workspaceId,
    required this.entryId,
    required this.titleLabel,
    required this.cwd,
    required this.connected,
    this.livePid,
  });

  final String workspaceId;
  final String entryId;
  final String titleLabel;
  final String cwd;
  final bool connected;
  final int? livePid;
}

/// Collects Resource Manager leaf bindings for [workspaceId] from plain refs.
List<ResourceBinding> collectResourceBindings({
  required String workspaceId,
  required List<ChatMemberShellRef> chatShells,
  required List<WorkspaceShellRef> workspaceShells,
  required List<GitWorktree> worktrees,
}) {
  final bindings = <ResourceBinding>[];

  for (final shell in chatShells) {
    if (shell.workspaceId != workspaceId) continue;
    final matched = _matchWorktree(shell.sessionPrimaryPath, worktrees);
    final member = shell.memberName.trim();
    final title = member.isEmpty
        ? shell.sessionTitle
        : '${shell.sessionTitle} · $member';
    bindings.add(
      ResourceBinding(
        key: 'chat:${shell.sessionId}:${shell.memberId}',
        kind: ResourceBindingKind.chatMember,
        groupKey: matched?.path ?? 'main',
        groupLabel: matched?.shortBranch ?? 'main',
        title: title,
        connected: shell.connected,
        sessionId: shell.sessionId,
        memberId: shell.memberId,
        livePid: shell.livePid,
      ),
    );
  }

  for (final shell in workspaceShells) {
    if (shell.workspaceId != workspaceId) continue;
    final matched = _matchWorktree(shell.cwd, worktrees);
    bindings.add(
      ResourceBinding(
        key: 'shell:${shell.workspaceId}:${shell.entryId}',
        kind: ResourceBindingKind.workspaceShell,
        groupKey: matched?.path ?? 'main',
        groupLabel: matched?.shortBranch ?? 'main',
        title: shell.titleLabel,
        connected: shell.connected,
        workspaceId: shell.workspaceId,
        shellEntryId: shell.entryId,
        livePid: shell.livePid,
      ),
    );
  }

  return bindings;
}

GitWorktree? _matchWorktree(String path, List<GitWorktree> worktrees) {
  final matchedPath = worktreePathForSessionPath(path, worktrees);
  if (matchedPath == null) return null;
  for (final w in worktrees) {
    if (w.path == matchedPath) return w;
  }
  return null;
}
