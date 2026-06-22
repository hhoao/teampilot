import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../models/workspace.dart';
import '../../../models/layout_preferences.dart';
import '../../../widgets/resizable_split_view.dart';
import '../../chat_page.dart';
import 'workspace_sidebar.dart';

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
        return s.primaryPath;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // One WorktreeCubit per opened workspace, shared by the sidebar (grouping +
    // create/delete) and ChatPage (current-worktree cwd). Keyed by workspace id
    // so switching workspaces rebuilds it against the new repo root.
    return BlocProvider<WorktreeCubit>(
      key: ValueKey('worktree-${widget.workspace.workspaceId}'),
      create: (ctx) => WorktreeCubit(workspaceId: widget.workspace.workspaceId)
        ..load(
          widget.workspace.primaryPath,
          // Default the current worktree to the active session's directory so
          // the file tree / source control open on the worktree being resumed.
          preferCurrentPath: _activeSessionPath(ctx),
        ),
      child: LayoutBuilder(
        builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        const minMain = LayoutPreferences.minWorkbenchMainWidth;
        const minSidebar = WorkspaceSidebarLayout.minWidth;
        const maxSidebarCap = WorkspaceSidebarLayout.maxWidth;
        final maxSidebar = (maxW - minMain).clamp(minSidebar, maxSidebarCap);
        final initialSidebar =
            (_sidebarWidth ?? WorkspaceSidebarLayout.defaultWidth).clamp(
              minSidebar,
              maxSidebar,
            );
        return ResizableSplitView(
          first: WorkspaceSidebar(
            workspace: widget.workspace,
            isPersonalWorkspace: widget.isPersonalWorkspace,
            profileId: widget.profileId,
            sessionTeamFilter: widget.sessionTeamFilter,
          ),
          second: BlocBuilder<WorktreeCubit, WorktreeState>(
            buildWhen: (a, b) =>
                a.currentWorktreePath != b.currentWorktreePath,
            builder: (context, wt) {
              // File tree + source control follow the current worktree; fall
              // back to the repo root (main worktree) when none is selected.
              final cwd = wt.currentWorktreePath.isNotEmpty
                  ? wt.currentWorktreePath
                  : widget.workspace.primaryPath;
              return ChatPage(
                cwd: cwd,
                additionalPaths: widget.workspace.additionalPaths,
                workspaceId: widget.workspace.workspaceId,
                tabScopeId: widget.tabScopeId,
                isPersonalWorkspace: widget.isPersonalWorkspace,
              );
            },
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
  }
}
