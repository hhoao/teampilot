import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../models/workspace.dart';
import '../../../services/git/git_worktree_service.dart';
import '../../../models/layout_preferences.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import '../../../services/workspace/workspace_tools_scope_registry.dart';
import '../../../services/workspace/workspace_worktree_registry.dart';
import '../../../widgets/resizable_split_view.dart';
import '../../chat_page.dart';
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
  double? _sidebarWidth;
  var _initialWorktreeBindDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialWorktreeBindDone) return;
    _initialWorktreeBindDone = true;
    // Bind before child initState (e.g. compose landing draft restore) so
    // WorktreeCubit.load is never called on an unbound lister. Tools-scope
    // sync re-binds when the storage target changes.
    final repoPath = widget.workspace.firstFolderPath;
    context.read<WorkspaceWorktreeRegistry>().cubitFor(
      workspaceId: widget.workspace.workspaceId,
      repoPath: repoPath,
    ).bindWorktreeService(
      GitWorktreeService(),
      repoPath: repoPath,
    );
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth;
                const minMain = LayoutPreferences.minWorkbenchMainWidth;
                const minSidebar = WorkspaceSidebarLayout.minWidth;
                const maxSidebarCap = WorkspaceSidebarLayout.maxWidth;
                final maxSidebar = (maxW - minMain).clamp(
                  minSidebar,
                  maxSidebarCap,
                );
                final initialSidebar =
                    (_sidebarWidth ?? WorkspaceSidebarLayout.defaultWidth)
                        .clamp(minSidebar, maxSidebar);
                return ResizableSplitView(
                  first: WorkspaceSidebar(
                    workspace: widget.workspace,
                    tabScopeId: widget.tabScopeId,
                  ),
                  second: _WorkspaceMainPane(
                    workspace: widget.workspace,
                    tabScopeId: widget.tabScopeId,
                    cwd: cwd,
                  ),
                  initialPrimarySize: initialSidebar,
                  minPrimarySize: minSidebar,
                  minSecondarySize: minMain,
                  maxPrimarySize: maxSidebar,
                  onPrimarySizeChanged: (width) => _sidebarWidth = width,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Right pane of the workspace split: compose landing or session workbench.
class _WorkspaceMainPane extends StatelessWidget {
  const _WorkspaceMainPane({
    required this.workspace,
    required this.tabScopeId,
    required this.cwd,
  });

  final Workspace workspace;
  final String tabScopeId;
  final String cwd;

  @override
  Widget build(BuildContext context) {
    return ChatPage(
      cwd: cwd,
      additionalPaths: workspace.extraFolderPaths,
      workspaceId: workspace.workspaceId,
      tabScopeId: tabScopeId,
    );
  }
}
