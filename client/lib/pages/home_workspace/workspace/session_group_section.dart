import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/session_groups_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_session.dart';
import '../../../models/session_group.dart';
import '../../../models/workspace.dart';
import '../../../utils/session/app_session_sort.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'workspace_session_actions.dart';
import 'workspace_sidebar_row_metrics.dart';

/// Approximate row height of a session tile in the sidebar list.
const double _groupSessionRowHeight = 46;

/// Max session rows shown before the user expands a group.
const int _groupCollapsedCap = 8;

/// Row count of the fixed-height scrollable an expanded group reveals.
const int _groupExpandedRowCount = 10;

/// One manual ("todo"-style) session group block: collapsible header,
/// tag-style member rows, context-managed lifecycle. The live group state is
/// resolved from [SessionGroupsCubit] by id so mutations from any surface
/// (menu, dialog, another tab sharing the cubit) reflect immediately.
class SessionGroupSection extends StatelessWidget {
  const SessionGroupSection({
    required this.group,
    required this.workspace,
    required this.tabScopeId,
    required this.sessionSort,
    this.highlightSessionId,
    super.key,
  });

  final SessionGroup group;
  final Workspace workspace;
  final String tabScopeId;
  final AppSessionSort sessionSort;
  final String? highlightSessionId;

  /// Fresh group state by id. The constructor [group] is only a snapshot —
  /// membership/name/collapse may have been mutated through the shared cubit
  /// (dialogs here, header menus, or another tab) after this widget was built.
  SessionGroup _groupIn(SessionGroupsState state) =>
      state.groupById(group.id) ?? group;

  void _toggleCollapse(BuildContext context) {
    context.read<SessionGroupsCubit>().toggleCollapsed(group.id);
  }

  Future<void> _rename(BuildContext context) async {
    final cubit = context.read<SessionGroupsCubit>();
    final l10n = context.l10n;
    final current = _groupIn(cubit.state);
    final name = await showTpTextPromptDialog(
      context,
      title: l10n.sessionGroupRenameTitle,
      initialText: current.name,
      labelText: l10n.sessionGroupNameLabel,
      confirmLabel: l10n.save,
      cancelLabel: l10n.cancel,
    );
    if (name == null || name.trim().isEmpty || name.trim() == current.name) {
      return;
    }
    cubit.renameGroup(current.id, name.trim());
  }

  Future<void> _confirmAndDelete(BuildContext context) async {
    final cubit = context.read<SessionGroupsCubit>();
    final l10n = context.l10n;
    final current = _groupIn(cubit.state);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.sessionGroupMenuRemove),
        content: Text(current.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    cubit.deleteGroup(group.id);
  }

  Future<void> _openAddSessionsDialog(BuildContext context) async {
    final cubit = context.read<SessionGroupsCubit>();
    final l10n = context.l10n;
    // Resolve membership now: prechecks and the Save diff must both start
    // from live state, not the constructor snapshot.
    final current = _groupIn(cubit.state);
    final workspaceSessions = context
        .read<ChatCubit>()
        .state
        .sessions
        .where((s) => s.workspaceId == workspace.workspaceId)
        .toList();
    if (workspaceSessions.isEmpty) return;

    final selected = current.sessionIds.toSet();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(l10n.sessionGroupAddSessionsTitle),
          content: SizedBox(
            width: 360,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: workspaceSessions.length,
              itemBuilder: (dialogContext, index) {
                final session = workspaceSessions[index];
                final title = session.resolveDisplayTitle(
                  l10n.defaultNewChatSessionTitle,
                );
                return CheckboxListTile(
                  value: selected.contains(session.sessionId),
                  onChanged: (checked) => setState(
                    () => checked ?? false
                        ? selected.add(session.sessionId)
                        : selected.remove(session.sessionId),
                  ),
                  title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    for (final session in workspaceSessions) {
      final member = selected.contains(session.sessionId);
      if (member != current.containsSession(session.sessionId)) {
        cubit.setMembership(current.id, session.sessionId, member: member);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch both cubits: membership and collapse flags may change via the
    // header menu or dialogs, and live sessions arrive through ChatCubit.
    final current = _groupIn(context.watch<SessionGroupsCubit>().state);
    final chatState = context.watch<ChatCubit>().state;
    final liveMembers = _liveGroupMembers(chatState, current, workspace);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SessionGroupHeader(
          group: current,
          liveMemberCount: liveMembers.length,
          onToggleCollapse: () => _toggleCollapse(context),
          onRename: () => unawaited(_rename(context)),
          onDelete: () => unawaited(_confirmAndDelete(context)),
          onAddSessions: () => unawaited(_openAddSessionsDialog(context)),
        ),
        if (!current.collapsed)
          _SessionGroupMemberList(
            group: current,
            workspace: workspace,
            tabScopeId: tabScopeId,
            sessionSort: sessionSort,
            highlightSessionId: highlightSessionId,
          ),
      ],
    );
  }

}

/// Group member ids resolved to live sessions of [workspace]'s sidebar,
/// preserving group order and dropping unknown/other-workspace ids.
List<AppSession> _liveGroupMembers(
  ChatState chatState,
  SessionGroup group,
  Workspace workspace,
) {
  final byId = {for (final s in chatState.sessions) s.sessionId: s};
  return [
    for (final id in group.sessionIds)
      if (byId[id] case final session?)
        if (session.workspaceId == workspace.workspaceId) session,
  ];
}

class _SessionGroupHeader extends StatefulWidget {
  const _SessionGroupHeader({
    required this.group,
    required this.liveMemberCount,
    required this.onToggleCollapse,
    required this.onRename,
    required this.onDelete,
    required this.onAddSessions,
  });

  final SessionGroup group;
  final int liveMemberCount;
  final VoidCallback onToggleCollapse;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onAddSessions;

  @override
  State<_SessionGroupHeader> createState() => _SessionGroupHeaderState();
}

class _SessionGroupHeaderState extends State<_SessionGroupHeader> {
  var _rowHovered = false;
  var _menuOpen = false;

  bool get _showRowActions => _rowHovered || _menuOpen;

  Future<void> _showContextMenu(TapDownDetails details) async {
    final l10n = context.l10n;
    setState(() => _menuOpen = true);
    final selected = await showTpActionMenuFromSpecsAtTap<String>(
      context: context,
      tapDetails: details,
      specs: [
        TpActionMenuSpec.item(
          value: 'add_sessions',
          icon: Icons.playlist_add_rounded,
          label: l10n.sessionGroupAddSessionsTitle,
        ),
        TpActionMenuSpec.item(
          value: 'rename',
          icon: Icons.drive_file_rename_outline,
          label: l10n.sessionGroupRenameTitle,
        ),
        TpActionMenuSpec.item(
          value: 'delete',
          icon: Icons.delete_outline_rounded,
          label: l10n.sessionGroupMenuRemove,
          destructive: true,
        ),
      ],
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    switch (selected) {
      case 'add_sessions':
        widget.onAddSessions();
      case 'rename':
        widget.onRename();
      case 'delete':
        widget.onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icons = context.tpIconSizes;
    final collapsed = widget.group.collapsed;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: TpHoverRow(
        forceShowTrailing: _menuOpen,
        forceHover: _menuOpen,
        padding: kWorkspaceSidebarRowPadding,
        hoverColor: workspaceSidebarRowHoverFill(cs),
        onHoverChanged: (hovered) => setState(() => _rowHovered = hovered),
        onTap: widget.onToggleCollapse,
        onSecondaryTapDown: (details) => unawaited(_showContextMenu(details)),
        trailing: TpIconButton(
          icon: Icons.add_rounded,
          compact: true,
          size: TpIconButton.kCompactSize,
          tooltip: context.l10n.sessionGroupAddSessionsTooltip,
          onTap: widget.onAddSessions,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Center(
                child: Icon(
                  _showRowActions
                      ? collapsed
                          ? Icons.chevron_right_rounded
                          : Icons.expand_more_rounded
                      : Icons.label_outline,
                  size: icons.md,
                  color: cs.onSurfaceVariant,
                ),
              ),
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
                      widget.group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
            Text(
              ' · ${widget.liveMemberCount}',
              maxLines: 1,
              style: TpTextStyles.of(
                context,
              ).mdColored(cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Member tiles for one manual group: sorted by the workspace sort, capped at
/// [_groupCollapsedCap]; expanding reveals a fixed-height scrollable viewport
/// so a large group never floods the sidebar. Read-only ordering — no drag.
class _SessionGroupMemberList extends StatefulWidget {
  const _SessionGroupMemberList({
    required this.group,
    required this.workspace,
    required this.tabScopeId,
    required this.sessionSort,
    this.highlightSessionId,
  });

  final SessionGroup group;
  final Workspace workspace;
  final String tabScopeId;
  final AppSessionSort sessionSort;
  final String? highlightSessionId;

  @override
  State<_SessionGroupMemberList> createState() =>
      _SessionGroupMemberListState();
}

class _SessionGroupMemberListState extends State<_SessionGroupMemberList> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final chatState = context.read<ChatCubit>().state;
    final all = sortAppSessions(
      _liveGroupMembers(chatState, widget.group, widget.workspace),
      sort: widget.sessionSort,
    );
    if (all.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          kWorkspaceSidebarGroupTextInset,
          0,
          kWorkspaceSidebarRowPadding.right,
          kWorkspaceSidebarRowPadding.bottom,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: kWorkspaceSidebarRowMinHeight,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.sessionGroupEmpty,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TpTextStyles.of(context).mdColored(
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
      );
    }

    final overflow = all.length - _groupCollapsedCap;
    final visible = (_showAll || overflow <= 0)
        ? all
        : all.take(_groupCollapsedCap).toList();
    final height =
        math.min(_groupExpandedRowCount, visible.length) *
        _groupSessionRowHeight;
    // Fixed-height scrollable only when rows overflow; otherwise natural
    // height with no scrolling. cacheExtent stays at 0 so a large expanded
    // group builds just the viewport's rows instead of eagerly mounting them.
    final scrollable = overflow > 0 || visible.length > _groupCollapsedCap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: scrollable ? height : null,
          child: ListView.builder(
            padding: EdgeInsets.zero,
            scrollCacheExtent: const ScrollCacheExtent.pixels(0),
            physics: scrollable
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            shrinkWrap: !scrollable,
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final session = visible[index];
              return SidebarSessionTile(
                key: ValueKey('manual-group-session-${session.sessionId}'),
                session: session,
                highlightSessionId: widget.highlightSessionId,
                tapThrottleKeyPrefix: 'manual_group_session',
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
          _SessionGroupShowMoreRow(
            label: _showAll ? l10n.worktreeShowLess : l10n.worktreeMore,
            onTap: () => setState(() => _showAll = !_showAll),
          ),
      ],
    );
  }
}

/// Muted "more / less" row aligned with session tiles; hover fill matches
/// [SidebarSessionTile] but slightly subtler.
class _SessionGroupShowMoreRow extends StatefulWidget {
  const _SessionGroupShowMoreRow({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  State<_SessionGroupShowMoreRow> createState() => _SessionGroupShowMoreRowState();
}

class _SessionGroupShowMoreRowState extends State<_SessionGroupShowMoreRow> {
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
                style: TpTextStyles.of(context).mdColored(
                  cs.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
