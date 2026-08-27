import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../cubits/layout_cubit.dart';
import '../../../cubits/mailbox_cubit.dart';
import '../../../cubits/workbench/workbench_cubit.dart';
import '../../../cubits/run_cubit.dart';
import '../../../cubits/session_groups_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../cubits/workspace_tools_cubit.dart';
import '../../../models/workspace.dart';
import '../../../services/commands/run_command_registrar.dart';
import '../../../services/commands/workspace_content_search_command_registrar.dart';
import '../../../services/commands/workspace_search_command_registrar.dart';
import '../../../services/workspace/workspace_run_registry.dart';
import '../../../services/io/local_filesystem.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import '../../../services/workspace/workspace_tools_scope_registry.dart';
import '../../../services/workspace/workspace_worktree_registry.dart';
import '../../../services/workspace/workspace_session_groups_registry.dart';
import '../../../utils/session/workspace_tab_session_scope.dart';
import '../../../utils/ui/app_keys.dart';
import '../../../utils/workspace/workspace_active_context.dart';
import '../../../utils/workspace/workspace_new_chat_active.dart';
import '../../../widgets/right_tools/right_tools_panel.dart';
import '../../../widgets/right_tools/right_tools_tool_views.dart';
import '../../../widgets/workspace_terminal_panel.dart';
import '../../chat_page.dart';
import '../../../widgets/workbench/workbench_shell_run_sync.dart';
import '../../workspace_ide/workspace_ide_shell.dart';
import 'workspace_ide_center.dart';
import 'workspace_route_active_scope.dart';
import 'workspace_search_dialog.dart';
import 'workspace_sidebar.dart';
import 'workspace_tools_scope_sync.dart';

class WorkspaceSplitPane extends StatefulWidget {
  const WorkspaceSplitPane({
    required this.workspace,
    required this.tabScopeId,
    super.key,
  });

  final Workspace workspace;
  final String tabScopeId;

  @override
  State<WorkspaceSplitPane> createState() => _WorkspaceSplitPaneState();
}

class _WorkspaceSplitPaneState extends State<WorkspaceSplitPane> {
  /// Bridges an IDE-shell split drag to center shell terminals' PTY resize hold.
  /// Owned here so it shares a lifetime with the workbench shell surfaces.
  final _terminalHold = WorkspaceTerminalHoldHandle();
  RunCubit? _boundRunCubit;
  RunCommandHost? _runCommandHost;
  WorkspaceSearchHost? _workspaceSearchHost;
  WorkspaceContentSearchHost? _contentSearchHost;
  late final void Function() _openWorkspaceSearch = _openSearch;
  late final void Function() _openContentSearch = _openContentSearchPanel;

  /// Bumped to focus the content-search query field; owned here so kept-alive
  /// workspace tabs keep the pending-focus channel across pane remounts.
  final ValueNotifier<int> _searchFocusRequest = ValueNotifier<int>(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _runCommandHost = context.read<RunCommandHost>();
    _workspaceSearchHost = context.read<WorkspaceSearchHost>();
    _contentSearchHost = context.read<WorkspaceContentSearchHost>();
    _syncRunCommandHost();
    _syncWorkspaceSearchHost();
    _syncContentSearchHost();
  }

  @override
  void dispose() {
    final cubit = _boundRunCubit;
    final host = _runCommandHost;
    if (cubit != null && host != null) {
      host.unbind(cubit);
    }
    _boundRunCubit = null;
    _workspaceSearchHost?.unbind(_openWorkspaceSearch);
    _contentSearchHost?.unbind(_openContentSearch);
    _searchFocusRequest.dispose();
    super.dispose();
  }

  void _openSearch() {
    if (!mounted) return;
    // This state sits above WorkspaceToolsScopeSync, so the scope has to be
    // read from its cubit (the same one provided below); falls back to a
    // local filesystem only when the plane has not resolved yet.
    final scopeCubit = context.read<WorkspaceToolsScopeRegistry>().cubitFor(
      tabScopeId: widget.tabScopeId,
      lifecycle: context.read<ChatCubit>().lifecycle,
    );
    unawaited(
      showWorkspaceSearchDialog(
        context,
        workspace: widget.workspace,
        fs: scopeCubit.state.tools?.context.filesystem ?? LocalFilesystem(),
      ),
    );
  }

  void _syncWorkspaceSearchHost() {
    final host = _workspaceSearchHost;
    if (host == null) return;
    final routeActive = WorkspaceRouteActiveScope.routeActiveOf(context);
    if (routeActive) {
      host.bind(_openWorkspaceSearch);
    } else {
      host.unbind(_openWorkspaceSearch);
    }
  }

  void _syncContentSearchHost() {
    final host = _contentSearchHost;
    if (host == null) return;
    final routeActive = WorkspaceRouteActiveScope.routeActiveOf(context);
    if (routeActive) {
      host.bind(_openContentSearch);
    } else {
      host.unbind(_openContentSearch);
    }
  }

  /// Ctrl+Shift+F: reveal the right-tools pane, select the content-search
  /// tab, then focus its query field.
  void _openContentSearchPanel() {
    if (!mounted) return;
    final workbench = context.read<WorkbenchCubit>();
    final layout = context.read<LayoutCubit>();
    final prefs = layout.state.preferences;
    if (!prefs.searchVisible) return;

    if (workspaceNewChatActive(workbench, widget.tabScopeId)) {
      layout.setLandingRightToolsOverride(true);
    } else {
      layout.setRightToolsVisible(true);
    }

    final chat = context.read<ChatCubit>();
    final active = WorkspaceActiveContext.resolve(
      workbench: workbench,
      chat: chat,
      launchProfiles: context.read<LaunchProfileCubit>(),
      tabScopeId: widget.tabScopeId,
    );

    MailboxCubit? mailboxCubit;
    try {
      mailboxCubit = context.read<MailboxCubit>();
    } on Object {
      mailboxCubit = null;
    }
    final team = active.team;
    final mailboxGate = RightToolsMailboxGate.resolve(
      isPersonalContext: active.isPersonal,
      team: team,
      hasTeamBus:
          scopedTeamBus(workbench, chat, widget.tabScopeId) != null &&
          mailboxCubit != null,
      boardVisible: prefs.boardVisible,
      unreadCount: 0,
    );
    // Mirrors the view order in RightToolsToolViews._buildViews: members,
    // fileTree, git, mailbox, board, then search last.
    final index = searchToolIndex(
      isPersonalContext: active.isPersonal,
      membersVisible: prefs.membersVisible && team != null,
      fileTreeVisible: prefs.fileTreeVisible,
      gitVisible: prefs.gitVisible,
      showMailbox: mailboxGate.showMailbox,
      showBoard: mailboxGate.showBoard,
    );
    context.read<WorkspaceToolsCubit>().setSelectedIndex(
      widget.tabScopeId,
      index,
    );

    // Defer the focus bump until the search panel has (re)mounted so it is
    // not lost to the panel's ValueListenable listener registration; keep
    // bumping a few frames in case the right-tools pane had to remount
    // (hidden -> visible) before the panel attached its listener.
    void bump() => _searchFocusRequest.value++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      bump();
      var remaining = 3;
      void retry() {
        if (!mounted || remaining <= 0) return;
        remaining--;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          bump();
          retry();
        });
      }

      retry();
    });
  }

  void _syncRunCommandHost() {
    final host = _runCommandHost;
    if (host == null) return;
    final routeActive = WorkspaceRouteActiveScope.routeActiveOf(context);
    final runCubit = context.read<WorkspaceRunRegistry>().cubitFor(
      tabScopeId: widget.tabScopeId,
      workspaceId: widget.workspace.workspaceId,
      folders: widget.workspace.folders,
    );
    if (routeActive) {
      host.bind(runCubit);
      _boundRunCubit = runCubit;
    } else if (identical(_boundRunCubit, runCubit)) {
      host.unbind(runCubit);
      _boundRunCubit = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatLifecycle = context.read<ChatCubit>().lifecycle;
    final scopeCubit = context.read<WorkspaceToolsScopeRegistry>().cubitFor(
      tabScopeId: widget.tabScopeId,
      lifecycle: chatLifecycle,
    );
    final worktreeCubit = context.read<WorkspaceWorktreeRegistry>().cubitFor(
      workspaceId: widget.workspace.workspaceId,
      repoPath: widget.workspace.firstFolderPath,
    );
    final sessionGroupsCubit = context
        .read<WorkspaceSessionGroupsRegistry>()
        .cubitFor(widget.workspace.workspaceId);
    final runCubit = context.read<WorkspaceRunRegistry>().cubitFor(
      tabScopeId: widget.tabScopeId,
      workspaceId: widget.workspace.workspaceId,
      folders: widget.workspace.folders,
    );
    return MultiBlocProvider(
      providers: [
        BlocProvider<WorkspaceToolsScopeCubit>.value(value: scopeCubit),
        BlocProvider<WorktreeCubit>.value(value: worktreeCubit),
        BlocProvider<RunCubit>.value(value: runCubit),
        BlocProvider<SessionGroupsCubit>.value(value: sessionGroupsCubit),
      ],
      child: BlocBuilder<WorktreeCubit, WorktreeState>(
        buildWhen: (a, b) => a.currentWorktreePath != b.currentWorktreePath,
        builder: (context, wt) {
          final cwd = wt.currentWorktreePath.isNotEmpty
              ? wt.currentWorktreePath
              : widget.workspace.firstFolderPath;
          final composeLanding = context.select<WorkbenchCubit, bool>(
            (w) => workspaceNewChatActive(w, widget.tabScopeId),
          );
          final landingInitialText = context.select<WorkbenchCubit, String?>(
            (w) => w.state.bar(widget.tabScopeId).center.landingInitialText,
          );
          final landingInitialTextRevision = context
              .select<WorkbenchCubit, int>(
                (w) => w.state
                    .bar(widget.tabScopeId)
                    .center
                    .landingInitialTextRevision,
              );
          final landingReferenceSessionId = context
              .select<WorkbenchCubit, String?>(
                (w) => w.state
                    .bar(widget.tabScopeId)
                    .center
                    .landingReferenceSessionId,
              );
          return WorkspaceToolsScopeSync(
            workspace: widget.workspace,
            cwd: cwd,
            tabScopeId: widget.tabScopeId,
            child: WorkbenchShellRunSync(
              workspaceId: widget.workspace.workspaceId,
              tabScopeId: widget.tabScopeId,
              holdHandle: _terminalHold,
              child: WorkspaceIdeShell(
                composeLanding: composeLanding,
                terminalHold: _terminalHold,
                onOpenWorkspaceManagement: () =>
                    openWorkspaceManagementRoute(context, widget.workspace),
                left: WorkspaceSidebar(
                  workspace: widget.workspace,
                  tabScopeId: widget.tabScopeId,
                  embedFooter:
                      !(TpSidebarScope.maybeOf(context)?.isMobile ?? false),
                ),
                // Unbound Chat pane skips ChatPageShell / workbench projection.
                center: buildWorkspaceIdeCenter(
                  newChat: composeLanding,
                  workspace: widget.workspace,
                  initialText: landingInitialText,
                  initialTextRevision: landingInitialTextRevision,
                  referencedSessionId: landingReferenceSessionId,
                  chatPage: ChatPage(
                    cwd: cwd,
                    additionalPaths: widget.workspace.extraFolderPaths,
                    workspaceId: widget.workspace.workspaceId,
                    tabScopeId: widget.tabScopeId,
                    holdHandle: _terminalHold,
                  ),
                ),
                // Side panes are off the first-open critical path: chrome +
                // landing paint first, then tools mount.
                right: TpDeferredMountShell(
                  delayFrames: 2,
                  child: _WorkspaceRightToolsPane(
                    cwd: cwd,
                    additionalPaths: widget.workspace.extraFolderPaths,
                    workspaceId: widget.workspace.workspaceId,
                    tabScopeId: widget.tabScopeId,
                    searchFocusRequest: _searchFocusRequest,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Right-tools pane for the IDE shell. Resolves its own active context so chat
/// churn only rebuilds this subtree, not the whole shell / center.
class _WorkspaceRightToolsPane extends StatelessWidget {
  const _WorkspaceRightToolsPane({
    required this.cwd,
    required this.additionalPaths,
    required this.workspaceId,
    required this.tabScopeId,
    required this.searchFocusRequest,
  });

  final String cwd;
  final List<String> additionalPaths;
  final String workspaceId;
  final String tabScopeId;
  final ValueNotifier<int> searchFocusRequest;

  @override
  Widget build(BuildContext context) {
    final chat = context.read<ChatCubit>();
    // Select only the fields this right-tools pane actually reads — avoids
    // rebuilding the tools subtree on every session working-state change.
    // composeLanding comes from the bar (single owner of landing state).
    final composeLanding = context.select<WorkbenchCubit, bool>(
      (w) => workspaceNewChatActive(w, tabScopeId),
    );
    // Rebuild whenever the bar's center-active session changes so the
    // team/personal context is never stale after a direct session switch.
    final _ = context.select<WorkbenchCubit, String?>(
      (w) => scopedActiveSessionId(w, tabScopeId),
    );
    final active = WorkspaceActiveContext.resolve(
      workbench: context.read<WorkbenchCubit>(),
      chat: chat,
      launchProfiles: context.read<LaunchProfileCubit>(),
      tabScopeId: tabScopeId,
    );
    final layoutState = context.watch<LayoutCubit>().state;
    final effectiveRight = composeLanding
        ? (layoutState.landingRightToolsOverride ?? false)
        : layoutState.preferences.rightToolsVisible;
    return RightToolsPanel(
      cwd: cwd,
      additionalPaths: additionalPaths,
      preferences: layoutState.preferences.copyWith(
        rightToolsVisible: effectiveRight,
      ),
      panelKey: AppKeys.rightToolsPanel,
      dismissDrawerOnAction: false,
      isPersonalContext: active.isPersonal,
      team: active.team,
      workspaceId: workspaceId,
      toolsScopeId: tabScopeId,
      searchFocusRequest: searchFocusRequest,
    );
  }
}
