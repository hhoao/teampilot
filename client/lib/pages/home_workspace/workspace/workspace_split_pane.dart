import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../cubits/layout_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../models/layout_preferences.dart';
import '../../../models/workspace.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import '../../../services/workspace/workspace_tools_scope_registry.dart';
import '../../../services/workspace/workspace_worktree_registry.dart';
import '../../../utils/app_keys.dart';
import '../../../utils/workspace_active_context.dart';
import '../../../widgets/deferred_mount_shell.dart';
import '../../../widgets/right_tools/right_tools_panel.dart';
import '../../../widgets/workspace_terminal_panel.dart';
import '../../chat_page.dart';
import '../../workspace_ide/workspace_ide_shell.dart';
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
  /// Bridges an IDE-shell split drag to the bottom terminal's PTY resize hold.
  /// Owned here so it shares a lifetime with the terminal panel instance.
  final _terminalHold = WorkspaceTerminalHoldHandle();

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
    return MultiBlocProvider(
      providers: [
        BlocProvider<WorkspaceToolsScopeCubit>.value(value: scopeCubit),
        BlocProvider<WorktreeCubit>.value(value: worktreeCubit),
      ],
      child: BlocBuilder<WorktreeCubit, WorktreeState>(
        buildWhen: (a, b) => a.currentWorktreePath != b.currentWorktreePath,
        builder: (context, wt) {
          final cwd = wt.currentWorktreePath.isNotEmpty
              ? wt.currentWorktreePath
              : widget.workspace.firstFolderPath;
          return WorkspaceToolsScopeSync(
            workspace: widget.workspace,
            cwd: cwd,
            tabScopeId: widget.tabScopeId,
            child: WorkspaceIdeShell(
              terminalHold: _terminalHold,
              left: WorkspaceSidebar(
                workspace: widget.workspace,
                tabScopeId: widget.tabScopeId,
              ),
              center: ChatPage(
                cwd: cwd,
                additionalPaths: widget.workspace.extraFolderPaths,
                workspaceId: widget.workspace.workspaceId,
                tabScopeId: widget.tabScopeId,
              ),
              // Side panes are off the first-open critical path: chrome +
              // landing paint first, then tools / terminal mount.
              right: DeferredMountShell(
                delayFrames: 2,
                child: _WorkspaceRightToolsPane(
                  cwd: cwd,
                  additionalPaths: widget.workspace.extraFolderPaths,
                  workspaceId: widget.workspace.workspaceId,
                  tabScopeId: widget.tabScopeId,
                ),
              ),
              // Keyed by workspace-group identity (never cwd): a same-workspace
              // cwd change keeps the panel State so the update flows through
              // didUpdateWidget instead of recreating (and stranding) sessions.
              bottom: DeferredMountShell(
                delayFrames: 2,
                child: WorkspaceTerminalPanel(
                  key: ValueKey('workspace-terminal-${widget.tabScopeId}'),
                  workspaceId: widget.tabScopeId,
                  workingDirectory: cwd,
                  holdHandle: _terminalHold,
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
    final active = WorkspaceActiveContext.resolve(
      chat: context.watch<ChatCubit>(),
      launchProfiles: context.read<LaunchProfileCubit>(),
      tabScopeId: tabScopeId,
    );
    final preferences = context.select<LayoutCubit, LayoutPreferences>(
      (c) => c.state.preferences,
    );
    return RightToolsPanel(
      cwd: cwd,
      additionalPaths: additionalPaths,
      preferences: preferences,
      panelKey: AppKeys.rightToolsPanel,
      dismissDrawerOnAction: false,
      isPersonalContext: active.isPersonal,
      team: active.team,
      workspaceId: workspaceId,
      toolsScopeId: tabScopeId,
    );
  }
}
