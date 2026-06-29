import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../models/workspace.dart';
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
    required this.isPersonalWorkspace,
    required this.profileId,
    required this.sessionTeamFilter,
    super.key,
  });

  final Workspace workspace;

  /// Scopes chat terminals and right-tools UI for this title-bar tab.
  final String tabScopeId;
  final bool isPersonalWorkspace;

  /// The launch identity the workspace was opened against ([LaunchProfile.id]).
  final String profileId;

  /// Empty for personal mode; team id when opened as a team.
  final String sessionTeamFilter;

  @override
  State<WorkspaceSplitPane> createState() => _WorkspaceSplitPaneState();
}

class _WorkspaceSplitPaneState extends State<WorkspaceSplitPane> {
  double? _sidebarWidth;

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
                    isPersonalWorkspace: widget.isPersonalWorkspace,
                    profileId: widget.profileId,
                    sessionTeamFilter: widget.sessionTeamFilter,
                    tabScopeId: widget.tabScopeId,
                  ),
                  second: ChatPage(
                    cwd: cwd,
                    additionalPaths: widget.workspace.extraFolderPaths,
                    workspaceId: widget.workspace.workspaceId,
                    tabScopeId: widget.tabScopeId,
                    profileId: widget.profileId,
                    isPersonalWorkspace: widget.isPersonalWorkspace,
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
