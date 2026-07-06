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
import '../../../theme/app_icon_sizes.dart';
import '../../../theme/app_text_styles.dart';
import '../../../utils/session_worktree_grouping.dart';
import '../../../utils/workspace_path_utils.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/app_toast/app_toast.dart';
import '../../../theme/app_toast_theme.dart';
import '../../../widgets/menu/sidebar_action_menu.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'worktree_delete_dialog.dart';
import 'workspace_session_actions.dart';

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

/// Shared left inset so group titles line up with [SidebarSessionTile] text.
const double kWorkspaceSidebarGroupTextInset = 8 + 24 + 8;

/// One collapsible worktree group in [WorkspaceSidebar]: a branch header (with
/// management menu) plus its session tiles. Selecting the header makes the
/// worktree the workspace's current one; the caret toggles collapse.
class WorktreeGroupSection extends StatelessWidget {
  const WorktreeGroupSection({
    required this.group,
    required this.workspace,
    required this.tabScopeId,
    required this.collapsed,
    required this.isCurrent,
    this.highlightSessionId,
    super.key,
  });

  final WorktreeGroup group;
  final Workspace workspace;
  final String tabScopeId;
  final bool collapsed;
  final bool isCurrent;
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

  Future<void> _selectWorktree(BuildContext context, String worktreePath) async {
    final cubit = context.read<WorktreeCubit>();
    final projectPath = group.projectFolderPath?.trim() ?? '';
    if (projectPath.isNotEmpty &&
        !workspacePathsEqual(cubit.state.repoPath, projectPath)) {
      await cubit.selectProject(projectPath, preferWorktreePath: worktreePath);
      return;
    }
    cubit.setCurrentWorktree(worktreePath);
  }

  String _repoPathForGroup(WorktreeCubit cubit) {
    final projectPath = group.projectFolderPath?.trim() ?? '';
    if (projectPath.isNotEmpty) return projectPath;
    return cubit.state.repoPath;
  }

  Future<void> _selectProjectFolder(BuildContext context) async {
    final projectPath = group.projectFolderPath?.trim() ?? '';
    if (projectPath.isEmpty) return;
    await context.read<WorktreeCubit>().selectProject(projectPath);
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
          isCurrent: isCurrent,
          label: label,
          launchPath: launchPath,
          onSelect: isProject
              ? () => unawaited(_selectProjectFolder(context))
              : wt != null
              ? () => unawaited(_selectWorktree(context, wt.path))
              : null,
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
            key: ValueKey('wt-sessions-${worktreeGroupCollapseKey(group)}'),
            sessions: group.sessions,
            workspace: workspace,
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
        variant: AppToastVariant.error,
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
        variant: AppToastVariant.error,
      );
    }
  }
}

class _WorktreeGroupHeader extends StatefulWidget {
  const _WorktreeGroupHeader({
    required this.collapsed,
    required this.isCurrent,
    required this.label,
    required this.launchPath,
    required this.onToggleCollapse,
    this.onSelect,
    this.onNewConversation,
    this.onCopyPath,
    this.onDelete,
  });

  final bool collapsed;
  final bool isCurrent;
  final String label;
  final String? launchPath;
  final VoidCallback? onSelect;
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
    final specs = <SidebarActionMenuSpec>[
      if (widget.onNewConversation != null)
        SidebarActionMenuSpec.item(
          value: 'new',
          icon: Icons.edit_outlined,
          label: l10n.worktreeNewConversationHere,
        ),
      if (widget.onCopyPath != null)
        SidebarActionMenuSpec.item(
          value: 'copy',
          icon: Icons.copy_rounded,
          label: l10n.worktreeMenuCopyPath,
        ),
      if (widget.onDelete != null)
        SidebarActionMenuSpec.item(
          value: 'delete',
          icon: Icons.delete_outline_rounded,
          label: l10n.worktreeMenuRemove,
          destructive: true,
        ),
    ];
    if (specs.isEmpty) return;

    setState(() => _menuOpen = true);
    final selected = await showSidebarActionMenuFromSpecsAtTap<String>(
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

    return MouseRegion(
      onEnter: (_) => setState(() => _rowHovered = true),
      onExit: (_) => setState(() => _rowHovered = false),
      child: Material(
        color: widget.isCurrent
            ? cs.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          onSecondaryTapDown: (details) => unawaited(_showContextMenu(details)),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onSelect,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(
                children: [
                  _GroupCollapseLeading(
                    collapsed: widget.collapsed,
                    showChevron: _showRowActions,
                    onToggle: widget.onToggleCollapse,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.onNewConversation != null)
                    AnimatedOpacity(
                      opacity: _showRowActions ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOut,
                      child: IgnorePointer(
                        ignoring: !_showRowActions,
                        child: AppIconButton(
                          icon: Icons.add_rounded,
                          compact: true,
                          size: AppIconButton.kCompactSize,
                          tooltip: null,
                          onTap: widget.onNewConversation,
                        ),
                      ),
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
    required this.onToggle,
  });

  final bool collapsed;
  final bool showChevron;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icons = context.appIconSizes;
    final icon = showChevron
        ? collapsed
              ? Icons.chevron_right_rounded
              : Icons.expand_more_rounded
        : Icons.folder_outlined;

    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Icon(
            icon,
            size: icons.md,
            color: cs.onSurfaceVariant,
          ),
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
    required this.workspace,
    this.highlightSessionId,
    super.key,
  });

  final List<AppSession> sessions;
  final Workspace workspace;
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
    final all = widget.sessions;
    final overflow = all.length - _cap;
    final visible = (_showAll || overflow <= 0) ? all : all.take(_cap).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final session in visible)
          SidebarSessionTile(
            key: ValueKey('worktree-session-${session.sessionId}'),
            session: session,
            highlightSessionId: widget.highlightSessionId,
            contentLeftInset: 0,
            tapThrottleKeyPrefix: 'worktree_sidebar_session',
            onTap: () {
              unawaited(
                openWorkspaceSessionTab(context, widget.workspace, session),
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

  static const _moreHoverTintAlpha = 0.07;

  Color _fillColor(ColorScheme cs) {
    if (!_hovered) return Colors.transparent;
    return Color.alphaBlend(
      cs.onSurface.withValues(alpha: _moreHoverTintAlpha),
      cs.surfaceContainer,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: _fillColor(cs),
          borderRadius: BorderRadius.circular(8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                kWorkspaceSidebarGroupTextInset,
                6,
                8,
                6,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 32),
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.of(context).body.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.55),
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
