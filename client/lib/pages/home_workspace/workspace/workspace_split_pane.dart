import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../cubits/layout_cubit.dart';
import '../../../cubits/run_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../models/layout_preferences.dart';
import '../../../models/workspace.dart';
import '../../../services/commands/run_command_registrar.dart';
import '../../../services/run/launch_adapter_protocol.dart';
import '../../../services/workspace/workspace_run_registry.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import '../../../services/workspace/workspace_tools_scope_registry.dart';
import '../../../services/workspace/workspace_worktree_registry.dart';
import '../../../utils/app_keys.dart';
import '../../../utils/workspace_active_context.dart';
import '../../../widgets/deferred_mount_shell.dart';
import '../../../widgets/right_tools/right_tools_panel.dart';
import '../../../widgets/run/run_toolbar.dart';
import '../../../widgets/workspace_bottom_dock.dart';
import '../../../widgets/workspace_terminal_panel.dart';
import '../../chat_page.dart';
import '../../workspace_ide/workspace_ide_shell.dart';
import 'workspace_route_active_scope.dart';
import 'workspace_sidebar.dart';
import 'workspace_tools_scope_sync.dart';

Future<Map<String, Object?>?> _pickRunActionResult(
  LaunchAdapterConfigurationEntry action,
) async {
  final result = await FilePicker.platform.pickFiles(type: FileType.any);
  final files = result?.files;
  if (files == null || files.isEmpty) return null;
  final path = files.first.path;
  if (path == null || path.isEmpty) return null;
  return {'path': path, 'name': p.basename(path)};
}

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
  RunCubit? _boundRunCubit;
  RunCommandHost? _runCommandHost;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _runCommandHost = context.read<RunCommandHost>();
    _syncRunCommandHost();
  }

  @override
  void dispose() {
    final cubit = _boundRunCubit;
    final host = _runCommandHost;
    if (cubit != null && host != null) {
      host.unbind(cubit);
    }
    _boundRunCubit = null;
    super.dispose();
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
          return WorkspaceToolsScopeSync(
            workspace: widget.workspace,
            cwd: cwd,
            tabScopeId: widget.tabScopeId,
            child: WorkspaceIdeShell(
              terminalHold: _terminalHold,
              topBar: RunToolbar(
                workspaceId: widget.workspace.workspaceId,
                showFolderLabels: widget.workspace.folders.length > 1,
                pickActionResult: _pickRunActionResult,
              ),
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
                child: WorkspaceBottomDock(
                  workspaceId: widget.tabScopeId,
                  workingDirectory: cwd,
                  holdHandle: _terminalHold,
                  terminalKey: ValueKey(
                    'workspace-terminal-${widget.tabScopeId}',
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
