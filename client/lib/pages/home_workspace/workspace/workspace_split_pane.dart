import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../models/workspace.dart';
import '../../../models/layout_preferences.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
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

  /// Working directory of the active session if it belongs to this workspace,
  /// used to seed the initial current worktree. Null when none applies.
  String? _activeSessionPath(BuildContext ctx) {
    final chat = ctx.read<ChatCubit>().state;
    final activeId = chat.activeSessionId;
    if (activeId == null || activeId.isEmpty) return null;
    for (final s in chat.sessions) {
      if (s.sessionId == activeId &&
          s.workspaceId == widget.workspace.workspaceId) {
        return s.firstFolderPath;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final chatLifecycle = context.read<ChatCubit>().lifecycle;
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => WorkspaceToolsScopeCubit(lifecycle: chatLifecycle),
        ),
        BlocProvider<WorktreeCubit>(
          key: ValueKey('worktree-${widget.workspace.workspaceId}'),
          create: (ctx) => WorktreeCubit(workspaceId: widget.workspace.workspaceId)
            ..load(
              widget.workspace.firstFolderPath,
              preferCurrentPath: _activeSessionPath(ctx),
            ),
        ),
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
                  ),
                  second: ChatPage(
                    cwd: cwd,
                    additionalPaths: widget.workspace.extraFolderPaths,
                    workspaceId: widget.workspace.workspaceId,
                    tabScopeId: widget.tabScopeId,
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
