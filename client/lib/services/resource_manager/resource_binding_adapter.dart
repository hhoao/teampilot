import '../../cubits/chat/model/chat_tab.dart';
import '../../models/git_worktree.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../terminal/workspace_terminal_registry.dart';
import 'resource_binding.dart';
import 'resource_binding_collector.dart';

/// Builds [ChatMemberShellRef] rows for open chat member shells in [workspaceId].
List<ChatMemberShellRef> chatMemberShellRefsForWorkspace({
  required String workspaceId,
  required Iterable<ChatTab> tabs,
  required String Function(ChatTab tab) sessionTitle,
  required String Function(ChatTab tab, String memberId) memberName,
}) {
  final refs = <ChatMemberShellRef>[];
  for (final tab in tabs) {
    if (tab.workspaceId != workspaceId &&
        tab.persistedSession?.workspaceId != workspaceId) {
      continue;
    }
    final session = tab.persistedSession;
    final title = sessionTitle(tab);
    final primaryPath = session?.firstFolderPath ?? '';
    for (final entry in tab.memberShells.entries) {
      final shell = entry.value;
      refs.add(
        ChatMemberShellRef(
          workspaceId: workspaceId,
          sessionId: tab.info.id,
          memberId: entry.key,
          sessionTitle: title,
          memberName: memberName(tab, entry.key),
          sessionPrimaryPath: primaryPath,
          connected: shell.isConnected || shell.isRunning,
          livePid: shell.pid,
        ),
      );
    }
  }
  return refs;
}

/// Builds [WorkspaceShellRef] rows from a terminal group.
List<WorkspaceShellRef> workspaceShellRefsForWorkspace({
  required String workspaceId,
  required WorkspaceTerminalGroup group,
}) {
  return [
    for (final entry in group.entries)
      WorkspaceShellRef(
        workspaceId: workspaceId,
        entryId: entry.id,
        titleLabel: entry.titleLabel.isNotEmpty
            ? entry.titleLabel
            : 'Terminal',
        cwd: entry.cwd,
        connected: entry.connected || entry.session.isRunning,
        livePid: entry.session.pid,
      ),
  ];
}

/// Collects live Resource Manager bindings for [workspaceId].
List<ResourceBinding> collectLiveResourceBindings({
  required String workspaceId,
  required Iterable<ChatTab> tabs,
  required WorkspaceTerminalGroup terminalGroup,
  required List<GitWorktree> worktrees,
  required String Function(ChatTab tab) sessionTitle,
  required String Function(ChatTab tab, String memberId) memberName,
  String? workspaceGroupLabel,
}) {
  return collectResourceBindings(
    workspaceId: workspaceId,
    chatShells: chatMemberShellRefsForWorkspace(
      workspaceId: workspaceId,
      tabs: tabs,
      sessionTitle: sessionTitle,
      memberName: memberName,
    ),
    workspaceShells: workspaceShellRefsForWorkspace(
      workspaceId: workspaceId,
      group: terminalGroup,
    ),
    worktrees: worktrees,
    workspaceGroupLabel: workspaceGroupLabel,
  );
}

/// Collects live bindings across every workspace (app-global Resource Manager).
///
/// Groups leaves by workspace id / display name.
List<ResourceBinding> collectLiveResourceBindingsAllWorkspaces({
  required Iterable<Workspace> workspaces,
  required Iterable<ChatTab> allTabs,
  required WorkspaceTerminalRegistry terminalRegistry,
  required String Function(ChatTab tab) sessionTitle,
  required String Function(ChatTab tab, String memberId) memberName,
}) {
  final bindings = <ResourceBinding>[];
  for (final workspace in workspaces) {
    final id = workspace.workspaceId;
    bindings.addAll(
      collectLiveResourceBindings(
        workspaceId: id,
        tabs: allTabs,
        terminalGroup: terminalRegistry.groupFor(id),
        worktrees: const [],
        sessionTitle: sessionTitle,
        memberName: memberName,
        workspaceGroupLabel: workspace.effectiveDisplay.isNotEmpty
            ? workspace.effectiveDisplay
            : id,
      ),
    );
  }
  return bindings;
}

/// Resolves a roster member display name from an optional team profile.
String resourceManagerMemberName({
  required ChatTab tab,
  required String memberId,
  TeamProfile? team,
}) {
  if (team != null) {
    for (final m in team.members) {
      if (m.id == memberId) {
        final name = m.name.trim();
        if (name.isNotEmpty) return name;
        break;
      }
    }
  }
  final session = tab.persistedSession;
  if (session != null && session.isSimple) return '';
  return memberId;
}

String resourceManagerSessionTitle(
  ChatTab tab, {
  required String emptyFallback,
}) {
  final session = tab.persistedSession;
  if (session != null) {
    return session.resolveDisplayTitle(emptyFallback);
  }
  final title = tab.info.title.trim();
  return title.isNotEmpty ? title : emptyFallback;
}
