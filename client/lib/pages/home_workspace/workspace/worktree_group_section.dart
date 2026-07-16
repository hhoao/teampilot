import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_session.dart';
import '../../../models/workspace.dart';
import '../../../repositories/session_repository.dart';
import '../../../services/git/git_worktree_service.dart';
import '../../../services/git/worktree_removal.dart';
import '../../../services/storage/runtime_context.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import '../../../utils/session/app_session_sort.dart';
import '../../../utils/session/session_reorder_merge.dart';
import '../../../utils/session/session_worktree_grouping.dart';
import '../../../utils/workspace/workspace_path_utils.dart';
import '../../../widgets/app_toast/app_toast.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'worktree_delete_dialog.dart';
import 'workspace_session_actions.dart';
import 'workspace_sidebar_row_metrics.dart';

/// Collapse-set key for a group: worktree path, project folder path, or orphan.
String worktreeGroupCollapseKey(WorktreeGroup group) {
  if (group.isProjectGroup) {
    final path = group.projectFolderPath?.trim() ?? '';
    return path.isEmpty
        ? '<project-orphan>'
        : 'project:${normalizeWorkspacePath(path)}';
  }
  return group.worktree?.path ?? '<orphan>';
}

/// Worktree create/remove on the workspace work-plane (native, WSL, or SSH git).
bool worktreeManagementEnabled(RuntimeContext workContext) =>
    workContext.mode == StorageBackendMode.native ||
    workContext.mode == StorageBackendMode.wsl ||
    workContext.mode == StorageBackendMode.ssh;

/// One collapsible worktree group in [WorkspaceSidebar]: header toggles collapse;
/// right-click opens management actions.
class WorktreeGroupSection extends StatelessWidget {
  const WorktreeGroupSection({
    required this.group,
    required this.workspace,
    required this.tabScopeId,
    required this.collapsed,
    required this.sessionSort,
    required this.workspaceOrderedSessionIds,
    required this.onSessionsReordered,
    this.highlightSessionId,
    super.key,
  });

  final WorktreeGroup group;
  final Workspace workspace;
  final String tabScopeId;
  final bool collapsed;
  final AppSessionSort sessionSort;

  /// Full sidebar session order (already sorted) used to merge a group-local
  /// drag back into a workspace-wide [sortOrder] stamp.
  final List<String> workspaceOrderedSessionIds;
  final ValueChanged<List<String>> onSessionsReordered;
  final String? highlightSessionId;

  GitWorktreeService? _worktreeService(BuildContext context) {
    final tools = WorkspaceToolsScope.maybeOf(context)?.tools;
    if (tools == null) return null;
    return GitWorktreeService.forContext(tools.context);
  }

  Future<void> _startConversationInWorktree(
    BuildContext context,
    String worktreePath,
  ) async {
    await showWorkspaceComposeLandingWithWorktree(
      context,
      workspace,
      tabScopeId: tabScopeId,
      worktreePath: worktreePath,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final wt = group.worktree;
    final isProject = group.isProjectGroup;
    final projectPath = group.projectFolderPath?.trim() ?? '';
    final label = group.sidebarLabel?.trim().isNotEmpty == true
        ? group.sidebarLabel!.trim()
        : isProject && projectPath.isNotEmpty
        ? Workspace.directoryName(projectPath)
        : wt == null
        ? l10n.worktreeOrphanGroup
        : wt.shortBranch;
    final launchPath = isProject && projectPath.isNotEmpty
        ? projectPath
        : wt?.path;
    final workContext = WorkspaceToolsScope.maybeOf(context)?.tools?.context;
    final manageable =
        wt != null &&
        !wt.isMainWorktree &&
        workContext != null &&
        worktreeManagementEnabled(workContext);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WorktreeGroupHeader(
          collapsed: collapsed,
          label: label,
          launchPath: launchPath,
          onToggleCollapse: () => context.read<WorktreeCubit>().toggleCollapsed(
            worktreeGroupCollapseKey(group),
          ),
          onNewConversation: launchPath == null
              ? null
              : () => unawaited(_startConversationInWorktree(context, launchPath)),
          onCopyPath: launchPath == null
              ? null
              : () => Clipboard.setData(ClipboardData(text: launchPath)),
          onDelete: wt != null && manageable
              ? () => unawaited(_confirmAndRemove(context, wt.path, label))
              : null,
        ),
        if (!collapsed && group.sessions.isNotEmpty)
          _GroupSessionList(
            sessions: group.sessions,
            sessionSort: sessionSort,
            workspaceOrderedSessionIds: workspaceOrderedSessionIds,
            onSessionsReordered: onSessionsReordered,
            workspace: workspace,
            tabScopeId: tabScopeId,
            highlightSessionId: highlightSessionId,
          ),
      ],
    );
  }

  Future<void> _confirmAndRemove(
    BuildContext context,
    String worktreePath,
    String branchLabel,
  ) async {
    final chatCubit = context.read<ChatCubit>();
    final repo = context.read<SessionRepository>();
    final cubit = context.read<WorktreeCubit>();
    final l10n = context.l10n;
    // A running agent's cwd would vanish under it — make the user stop first.
    final working = chatCubit.state.workingSessionIds;
    final hasBusy = group.sessions.any((s) => working.contains(s.sessionId));
    if (hasBusy) {
      AppToast.show(
        context,
        message: l10n.worktreeDeleteBusyWarning,
        variant: TpToastVariant.error,
      );
      return;
    }
    final dirty =
        await _worktreeService(context)?.isDirty(worktreePath) ?? false;
    if (!context.mounted) return;
    final result = await showWorktreeDeleteDialog(
      context,
      branchLabel: branchLabel,
      sessionCount: group.sessions.length,
      requireForce: dirty,
    );
    if (result == null) return;
    try {
      final service = _worktreeService(context);
      if (service == null) return;
      await removeWorktreeWithSessions(
        service: service,
        repoPath: _repoPathForGroup(cubit),
        worktreePath: worktreePath,
        worktree: group.worktree,
        options: WorktreeDeleteOptions(
          force: result.force,
          deleteBranch: result.deleteBranch,
          deleteSessions: result.deleteSessions,
        ),
        sessionsInGroup: group.sessions,
        deleteSession: (id) => chatCubit.deleteSession(repo, id),
      );
      await cubit.load(_repoPathForGroup(cubit));
    } on Object catch (error) {
      if (!context.mounted) return;
      AppToast.show(
        context,
        message: l10n.worktreeDeleteFailed(error.toString()),
        variant: TpToastVariant.error,
      );
    }
  }

  String _repoPathForGroup(WorktreeCubit cubit) {
    final projectPath = group.projectFolderPath?.trim() ?? '';
    if (projectPath.isNotEmpty) return projectPath;
    return cubit.state.repoPath;
  }
}

class _WorktreeGroupHeader extends StatefulWidget {
  const _WorktreeGroupHeader({
    required this.collapsed,
    required this.label,
    required this.launchPath,
    required this.onToggleCollapse,
    this.onNewConversation,
    this.onCopyPath,
    this.onDelete,
  });

  final bool collapsed;
  final String label;
  final String? launchPath;
  final VoidCallback onToggleCollapse;
  final VoidCallback? onNewConversation;
  final VoidCallback? onCopyPath;
  final VoidCallback? onDelete;

  @override
  State<_WorktreeGroupHeader> createState() => _WorktreeGroupHeaderState();
}

class _WorktreeGroupHeaderState extends State<_WorktreeGroupHeader> {
  var _rowHovered = false;
  var _menuOpen = false;

  bool get _showRowActions => _rowHovered || _menuOpen;

  Future<void> _showContextMenu(TapDownDetails details) async {
    final l10n = context.l10n;
    final specs = <TpActionMenuSpec>[
      if (widget.onNewConversation != null)
        TpActionMenuSpec.item(
          value: 'new',
          icon: Icons.edit_outlined,
          label: l10n.worktreeNewConversationHere,
        ),
      if (widget.onCopyPath != null)
        TpActionMenuSpec.item(
          value: 'copy',
          icon: Icons.copy_rounded,
          label: l10n.worktreeMenuCopyPath,
        ),
      if (widget.onDelete != null)
        TpActionMenuSpec.item(
          value: 'delete',
          icon: Icons.delete_outline_rounded,
          label: l10n.worktreeMenuRemove,
          destructive: true,
        ),
    ];
    if (specs.isEmpty) return;

    setState(() => _menuOpen = true);
    final selected = await showTpActionMenuFromSpecsAtTap<String>(
      context: context,
      tapDetails: details,
      specs: specs,
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    if (selected == null) return;

    switch (selected) {
      case 'new':
        widget.onNewConversation?.call();
      case 'copy':
        widget.onCopyPath?.call();
      case 'delete':
        widget.onDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rowFill = _rowHovered || _menuOpen
        ? workspaceSidebarRowHoverFill(cs)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _rowHovered = true),
        onExit: (_) => setState(() => _rowHovered = false),
        child: Material(
          color: rowFill,
          borderRadius: BorderRadius.circular(8),
          child: GestureDetector(
            onSecondaryTapDown: (details) => unawaited(_showContextMenu(details)),
            onTap: widget.onToggleCollapse,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: kWorkspaceSidebarRowPadding,
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _GroupCollapseLeading(
                      collapsed: widget.collapsed,
                      showChevron: _showRowActions,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: kWorkspaceSidebarRowMinHeight,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.onNewConversation != null && _showRowActions)
                      TpIconButton(
                        icon: Icons.add_rounded,
                        compact: true,
                        size: TpIconButton.kCompactSize,
                        tooltip: null,
                        onTap: widget.onNewConversation,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }
}

/// Folder icon by default; chevron when the group row is hovered.
class _GroupCollapseLeading extends StatelessWidget {
  const _GroupCollapseLeading({
    required this.collapsed,
    required this.showChevron,
  });

  final bool collapsed;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icons = context.tpIconSizes;
    final icon = showChevron
        ? collapsed
              ? Icons.chevron_right_rounded
              : Icons.expand_more_rounded
        : Icons.folder_outlined;

    return SizedBox(
      width: 24,
      height: 24,
      child: Center(
        child: Icon(
          icon,
          size: icons.md,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Session tiles for one worktree group, capped at [_cap] with a "show
/// more / show less" toggle so a busy worktree doesn't flood the sidebar.
class _GroupSessionList extends StatefulWidget {
  const _GroupSessionList({
    required this.sessions,
    required this.sessionSort,
    required this.workspaceOrderedSessionIds,
    required this.onSessionsReordered,
    required this.workspace,
    required this.tabScopeId,
    this.highlightSessionId,
  });

  final List<AppSession> sessions;
  final AppSessionSort sessionSort;
  final List<String> workspaceOrderedSessionIds;
  final ValueChanged<List<String>> onSessionsReordered;
  final Workspace workspace;
  final String tabScopeId;
  final String? highlightSessionId;

  @override
  State<_GroupSessionList> createState() => _GroupSessionListState();
}

class _GroupSessionListState extends State<_GroupSessionList> {
  static const _cap = 5;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final all = sortAppSessions(widget.sessions, sort: widget.sessionSort);
    final overflow = all.length - _cap;
    final visible = (_showAll || overflow <= 0) ? all : all.take(_cap).toList();
    final visibleIds = [for (final s in visible) s.sessionId];
    final allIds = [for (final s in all) s.sessionId];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          padding: EdgeInsets.zero,
          itemCount: visible.length,
          onReorderItem: (oldIndex, newIndex) {
            final groupOrdered = reorderVisibleSessionIds(
              allIds: allIds,
              visibleIds: visibleIds,
              oldIndex: oldIndex,
              newIndex: newIndex,
            );
            widget.onSessionsReordered(
              mergeGroupSessionReorder(
                workspaceOrderedIds: widget.workspaceOrderedSessionIds,
                groupOrderedIds: groupOrdered,
              ),
            );
          },
          itemBuilder: (context, index) {
            final session = visible[index];
            return SidebarSessionTile(
              key: ValueKey('worktree-session-${session.sessionId}'),
              session: session,
              index: index,
              highlightSessionId: widget.highlightSessionId,
              contentLeftInset: 0,
              tapThrottleKeyPrefix: 'worktree_sidebar_session',
              onTap: () {
                unawaited(
                  openWorkspaceSessionTab(
                    context,
                    widget.workspace,
                    session,
                    tabScopeId: widget.tabScopeId,
                  ),
                );
              },
            );
          },
        ),
        if (overflow > 0)
          _GroupShowMoreRow(
            label: _showAll ? l10n.worktreeShowLess : l10n.worktreeMore,
            onTap: () => setState(() => _showAll = !_showAll),
          ),
      ],
    );
  }
}

/// Muted "more / less" row aligned with session tiles; hover fill matches
/// [_SidebarTile] but slightly subtler.
class _GroupShowMoreRow extends StatefulWidget {
  const _GroupShowMoreRow({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  State<_GroupShowMoreRow> createState() => _GroupShowMoreRowState();
}

class _GroupShowMoreRowState extends State<_GroupShowMoreRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: _hovered ? workspaceSidebarRowHoverFill(cs) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                kWorkspaceSidebarGroupTextInset,
                kWorkspaceSidebarRowPadding.top,
                kWorkspaceSidebarRowPadding.right,
                kWorkspaceSidebarRowPadding.bottom,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: kWorkspaceSidebarRowMinHeight,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TpTextStyles.of(context).mdColored(cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
