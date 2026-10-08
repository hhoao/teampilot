import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import '../../../utils/session/app_session_sort.dart';
import '../../../utils/session/session_reorder_merge.dart';
import '../../../utils/session/session_worktree_grouping.dart';
import '../../../widgets/home_storage_scope.dart';
import '../../../utils/workspace/workspace_path_utils.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'worktree_directory_actions.dart';
import 'workspace_session_actions.dart';
import 'workspace_sidebar_probe.dart';
import 'workspace_sidebar_row_metrics.dart';
import 'workspace_nested_scroll_physics.dart';

export 'worktree_directory_actions.dart';

/// Collapse-set key for a group: worktree path, project folder path, or orphan.
String worktreeGroupCollapseKey(
  WorktreeGroup group, {
  required bool usesPosixPaths,
}) {
  if (group.isProjectGroup) {
    final path = group.projectFolderPath?.trim() ?? '';
    return path.isEmpty
        ? '<project-orphan>'
        : 'project:${normalizeWorkspacePath(path, usesPosixPaths: usesPosixPaths)}';
  }
  return group.worktree?.path ?? '<orphan>';
}

/// Approximate row height of a session tile in the sidebar list.
const double _groupSessionRowHeight = 46;

/// Max session rows shown before the user expands a group.
const int _groupCollapsedCap = 8;

/// Row count of the fixed-height scrollable an expanded group reveals.
const int _groupExpandedRowCount = 10;

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

    String collapseKey() => worktreeGroupCollapseKey(
      group,
      usesPosixPaths: homeStorageOf(context).usesPosixPaths,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WorktreeGroupHeader(
          collapseKey: collapseKey(),
          collapsed: collapsed,
          label: label,
          launchPath: launchPath,
          onToggleCollapse: () =>
              context.read<WorktreeCubit>().toggleCollapsed(collapseKey()),
          onNewConversation: launchPath == null
              ? null
              : () => unawaited(
                  _startConversationInWorktree(context, launchPath),
                ),
          onCopyPath: launchPath == null
              ? null
              : () => Clipboard.setData(ClipboardData(text: launchPath)),
          onDelete: wt != null && manageable
              ? () => unawaited(
                  confirmAndRemoveWorktree(
                    context: context,
                    group: group,
                    workspace: workspace,
                    branchLabel: label,
                  ),
                )
              : null,
        ),
        if (!collapsed && group.sessions.isNotEmpty)
          _GroupSessionList(
            sessionIds: [for (final s in group.sessions) s.sessionId],
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
}

class _WorktreeGroupHeader extends StatefulWidget {
  const _WorktreeGroupHeader({
    required this.collapseKey,
    required this.collapsed,
    required this.label,
    required this.launchPath,
    required this.onToggleCollapse,
    this.onNewConversation,
    this.onCopyPath,
    this.onDelete,
  });

  final String collapseKey;
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
    setState(() => _menuOpen = true);
    final selected = await showWorktreeDirectoryContextMenu(
      context,
      tapDetails: details,
      launchPath: widget.launchPath,
      canRemove: widget.onDelete != null,
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    if (selected == null) return;

    switch (selected) {
      case WorktreeDirectoryMenuAction.newConversation:
        widget.onNewConversation?.call();
      case WorktreeDirectoryMenuAction.copyPath:
        widget.onCopyPath?.call();
      case WorktreeDirectoryMenuAction.remove:
        widget.onDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SidebarRebuildProbe(
      key: ValueKey('worktree-group-header-probe-${widget.collapseKey}'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: TpHoverRow(
          forceShowTrailing: _menuOpen,
          forceHover: _menuOpen,
          padding: kWorkspaceSidebarRowPadding,
          hoverColor: workspaceSidebarRowHoverFill(cs),
          onHoverChanged: (hovered) => setState(() => _rowHovered = hovered),
          onTap: widget.onToggleCollapse,
          onSecondaryTapDown: (details) => unawaited(_showContextMenu(details)),
          trailing: widget.onNewConversation != null
              ? TpIconButton(
                  icon: Icons.add_rounded,
                  compact: true,
                  size: TpIconButton.kCompactSize,
                  tooltip: null,
                  onTap: widget.onNewConversation,
                )
              : null,
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
            ],
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
        child: Icon(icon, size: icons.md, color: cs.onSurfaceVariant),
      ),
    );
  }
}

/// Session tiles for one worktree group. Collapsed (default) shows at most
/// [_groupCollapsedCap] rows at their natural height; the "more" toggle
/// expands the group to a fixed [_groupExpandedRowCount]-row scrollable, so a
/// busy worktree never floods the sidebar.
class _GroupSessionList extends StatefulWidget {
  const _GroupSessionList({
    required this.sessionIds,
    required this.sessionSort,
    required this.workspaceOrderedSessionIds,
    required this.onSessionsReordered,
    required this.workspace,
    required this.tabScopeId,
    this.highlightSessionId,
  });

  final List<String> sessionIds;
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
  bool _showAll = false;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final chatState = context.read<ChatCubit>().state;
    final byId = {for (final s in chatState.sessions) s.sessionId: s};
    final all = sortAppSessions([
      for (final id in widget.sessionIds)
        if (byId[id] case final session?) session,
    ], sort: widget.sessionSort);
    final allIds = [for (final s in all) s.sessionId];
    final overflow = all.length - _groupCollapsedCap;
    final visible = (_showAll || overflow <= 0)
        ? all
        : all.take(_groupCollapsedCap).toList();
    final visibleIds = [for (final s in visible) s.sessionId];
    final outerPosition = Scrollable.maybeOf(context)?.position;

    // Collapsed: rows at natural height (no scroll). Expanded: fixed
    // row-count viewport that keeps the list lazy, so a busy group never
    // builds every session tile in one frame.
    final height =
        math.min(_groupExpandedRowCount, visible.length) *
        _groupSessionRowHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: ReorderableListView.builder(
            scrollController: _scrollController,
            primary: false,
            buildDefaultDragHandles: false,
            padding: EdgeInsets.zero,
            itemExtent: _groupSessionRowHeight,
            scrollCacheExtent: const ScrollCacheExtent.pixels(0),
            itemCount: visible.length,
            physics: WorkspaceNestedScrollPhysics(outerPosition: outerPosition),
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
              final sessionId = visibleIds[index];
              final session = byId[sessionId];
              if (session == null) return SizedBox(key: ValueKey(sessionId));
              return SidebarSessionTile(
                key: ValueKey('worktree-session-$sessionId'),
                session: session,
                index: index,
                highlightSessionId: widget.highlightSessionId,
                contentLeftInset: 0,
                tapThrottleKeyPrefix: 'worktree_sidebar_session',
                onTap: () => openWorkspaceSessionTab(
                  context,
                  widget.workspace,
                  session,
                  tabScopeId: widget.tabScopeId,
                ),
              );
            },
          ),
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
  const _GroupShowMoreRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_GroupShowMoreRow> createState() => _GroupShowMoreRowState();
}

class _GroupShowMoreRowState extends State<_GroupShowMoreRow> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: TpHover(
        onTap: widget.onTap,
        hoverColor: workspaceSidebarRowHoverFill(cs),
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
                style: TpTextStyles.of(
                  context,
                ).mdColored(cs.onSurface.withValues(alpha: 0.55)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
