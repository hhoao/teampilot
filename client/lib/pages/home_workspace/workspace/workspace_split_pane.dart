import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../cubits/layout_cubit.dart';
import '../../../cubits/run_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../models/workspace.dart';
import '../../../services/commands/run_command_registrar.dart';
import '../../../services/commands/workspace_search_command_registrar.dart';
import '../../../services/workspace/workspace_run_registry.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import '../../../services/workspace/workspace_tools_scope_registry.dart';
import '../../../services/workspace/workspace_worktree_registry.dart';
import '../../../utils/ui/app_keys.dart';
import '../../../utils/workspace/workspace_active_context.dart';
import '../../../utils/workspace/workspace_new_chat_active.dart';
import '../../../widgets/right_tools/right_tools_panel.dart';
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
  late final void Function() _openWorkspaceSearch = _openSearch;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _runCommandHost = context.read<RunCommandHost>();
    _workspaceSearchHost = context.read<WorkspaceSearchHost>();
    _syncRunCommandHost();
    _syncWorkspaceSearchHost();
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
    super.dispose();
  }

  void _openSearch() {
    if (!mounted) return;
    unawaited(
      showWorkspaceSearchDialog(context, workspace: widget.workspace),
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
      ],
      child: BlocBuilder<WorktreeCubit, WorktreeState>(
        buildWhen: (a, b) => a.currentWorktreePath != b.currentWorktreePath,
        builder: (context, wt) {
          final cwd = wt.currentWorktreePath.isNotEmpty
              ? wt.currentWorktreePath
              : widget.workspace.firstFolderPath;
          final composeLanding = context.select<ChatCubit, bool>(
            (c) => workspaceNewChatActive(c, widget.tabScopeId),
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
  });

  final String cwd;
  final List<String> additionalPaths;
  final String workspaceId;
  final String tabScopeId;

  @override
  Widget build(BuildContext context) {
    final chat = context.read<ChatCubit>();
    // Watch only the fields that this right-tools pane actually reads — avoids
    // rebuilding the tools subtree on every session working-state change.
    final composeLanding = context.select<ChatCubit, bool>(
      (c) => workspaceNewChatActive(c, tabScopeId),
    );
    final active = WorkspaceActiveContext.resolve(
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
    );
  }
}
