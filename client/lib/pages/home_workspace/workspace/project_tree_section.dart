import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_session.dart';
import '../../../models/git_worktree.dart';
import '../../../models/workspace.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import '../../../utils/session/session_project_grouping.dart';
import '../../../utils/session/session_worktree_grouping.dart';
import '../../../utils/workspace/workspace_path_utils.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'worktree_directory_actions.dart';
import 'workspace_session_actions.dart';
import 'workspace_sidebar_row_metrics.dart';
import 'workspace_nested_scroll_physics.dart';

const String _projectOrphanKey = '<project-orphan>';

const double _projectTreeSessionRowHeight = 46;
const int _projectTreeSessionCollapsedCap = 8;
const int _projectTreeSessionExpandedRowCount = 10;

class ProjectTreeSection extends StatefulWidget {
  const ProjectTreeSection({
    required this.groups,
    required this.workspace,
    required this.tabScopeId,
    required this.highlightSessionId,
    this.worktreesByProjectPath = const {},
    this.usesPosixPaths = true,
    super.key,
  });

  final List<ProjectSessionGroup> groups;
  final Workspace workspace;
  final String tabScopeId;
  final String? highlightSessionId;
  final Map<String, List<GitWorktree>> worktreesByProjectPath;
  final bool usesPosixPaths;

  @override
  State<ProjectTreeSection> createState() => _ProjectTreeSectionState();
}

class _ProjectTreeSectionState extends State<ProjectTreeSection> {
  final Set<String> _collapsedPaths = <String>{};

  String _groupKey(ProjectSessionGroup group) =>
      group.projectPath ?? _projectOrphanKey;

  List<GitWorktree> _worktreesForProject(String? projectPath) {
    if (projectPath == null || projectPath.isEmpty) return const [];
    for (final entry in widget.worktreesByProjectPath.entries) {
      if (workspacePathsEqual(
        entry.key,
        projectPath,
        usesPosixPaths: widget.usesPosixPaths,
      )) {
        return entry.value;
      }
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final groups = [
      for (final group in widget.groups)
        if (group.sessions.isNotEmpty ||
            _worktreesForProject(group.projectPath).isNotEmpty)
          (
            group: group,
            worktrees:
                group.isOther || _worktreesForProject(group.projectPath).isEmpty
                ? const <WorktreeGroup>[]
                : groupSessionsByWorktree(
                    worktrees: _worktreesForProject(group.projectPath),
                    sessions: group.sessions,
                    usesPosixPaths: widget.usesPosixPaths,
                  ),
          ),
    ];
    if (groups.isEmpty) {
      return TpEmptyState(
        icon: Icons.forum_outlined,
        title: context.l10n.homeWorkspaceNoConversations,
        centered: true,
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final entry = groups[index];
        final group = entry.group;
        final groupKey = _groupKey(group);
        final collapsed = _collapsedPaths.contains(groupKey);
        return _ProjectTreeGroup(
          key: ValueKey('project-tree-group-$groupKey'),
          group: group,
          worktrees: entry.worktrees,
          workspace: widget.workspace,
          tabScopeId: widget.tabScopeId,
          highlightSessionId: widget.highlightSessionId,
          collapsed: collapsed,
          onToggle: () => setState(() {
            if (collapsed) {
              _collapsedPaths.remove(groupKey);
            } else {
              _collapsedPaths.add(groupKey);
            }
          }),
        );
      },
    );
  }
}

class _ProjectTreeGroup extends StatefulWidget {
  const _ProjectTreeGroup({
    required this.group,
    required this.worktrees,
    required this.workspace,
    required this.tabScopeId,
    required this.highlightSessionId,
    required this.collapsed,
    required this.onToggle,
    super.key,
  });

  final ProjectSessionGroup group;
  final List<WorktreeGroup> worktrees;
  final Workspace workspace;
  final String tabScopeId;
  final String? highlightSessionId;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  State<_ProjectTreeGroup> createState() => _ProjectTreeGroupState();
}

class _ProjectTreeGroupState extends State<_ProjectTreeGroup> {
  var _hovered = false;
  var _menuOpen = false;
  final Set<String> _collapsedWorktrees = <String>{};

  String? get _launchPath {
    final path = widget.group.projectPath?.trim() ?? '';
    return widget.group.isOther || path.isEmpty ? null : path;
  }

  Future<void> _showContextMenu(TapDownDetails details) async {
    setState(() => _menuOpen = true);
    final selected = await showWorktreeDirectoryContextMenu(
      context,
      tapDetails: details,
      launchPath: _launchPath,
      canRemove: false,
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    switch (selected) {
      case WorktreeDirectoryMenuAction.newConversation:
        final path = _launchPath;
        if (path != null) {
          unawaited(
            showWorkspaceComposeLandingWithWorktree(
              context,
              widget.workspace,
              tabScopeId: widget.tabScopeId,
              worktreePath: path,
            ),
          );
        }
      case WorktreeDirectoryMenuAction.copyPath:
        final path = _launchPath;
        if (path != null) unawaited(copyWorktreeDirectoryPath(path));
      case WorktreeDirectoryMenuAction.remove:
      case null:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = widget.group.isOther
        ? context.l10n.projectTreeOther
        : widget.group.label;
    final icon = _hovered
        ? widget.collapsed
              ? Icons.chevron_right_rounded
              : Icons.expand_more_rounded
        : Icons.folder_outlined;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpHoverRow(
          key: ValueKey(
            'project-tree-node-${widget.group.projectPath ?? '<project-orphan>'}',
          ),
          forceShowTrailing: _menuOpen,
          forceHover: _menuOpen,
          padding: kWorkspaceSidebarRowPadding,
          hoverColor: workspaceSidebarRowHoverFill(cs),
          onHoverChanged: (hovered) => setState(() => _hovered = hovered),
          onTap: widget.onToggle,
          onSecondaryTapDown: (details) => unawaited(_showContextMenu(details)),
          trailing: _launchPath == null
              ? null
              : TpIconButton(
                  icon: Icons.add_rounded,
                  compact: true,
                  size: TpIconButton.kCompactSize,
                  tooltip: null,
                  onTap: () => unawaited(
                    showWorkspaceComposeLandingWithWorktree(
                      context,
                      widget.workspace,
                      tabScopeId: widget.tabScopeId,
                      worktreePath: _launchPath!,
                    ),
                  ),
                ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: Icon(
                    _menuOpen
                        ? (widget.collapsed
                              ? Icons.chevron_right_rounded
                              : Icons.expand_more_rounded)
                        : icon,
                    size: context.tpIconSizes.md,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (!widget.collapsed) ...[
          if (widget.worktrees.isEmpty)
            _ProjectTreeSessionList(
              key: ValueKey(
                'project-tree-session-list-state-${widget.group.projectPath ?? _projectOrphanKey}',
              ),
              sessions: widget.group.sessions,
              workspace: widget.workspace,
              tabScopeId: widget.tabScopeId,
              highlightSessionId: widget.highlightSessionId,
              contentLeftInset: 0,
              sessionKeyPrefix: 'project-tree-session',
              viewportKey: ValueKey(
                'project-tree-session-list-${widget.group.projectPath ?? _projectOrphanKey}',
              ),
            ),
          for (final worktreeGroup in widget.worktrees)
            ..._worktreeChildren(context, worktreeGroup),
        ],
      ],
    );
  }

  List<Widget> _worktreeChildren(
    BuildContext context,
    WorktreeGroup worktreeGroup,
  ) {
    final worktree = worktreeGroup.worktree;
    if (worktree == null) {
      final sessionKeyPrefix = widget.worktrees.length == 1
          ? 'project-tree-session'
          : 'project-tree-orphan-session';
      return [
        _ProjectTreeSessionList(
          sessions: worktreeGroup.sessions,
          workspace: widget.workspace,
          tabScopeId: widget.tabScopeId,
          highlightSessionId: widget.highlightSessionId,
          contentLeftInset: 0,
          sessionKeyPrefix: sessionKeyPrefix,
        ),
      ];
    }
    return [
      _ProjectTreeWorktree(
        group: worktreeGroup,
        workspace: widget.workspace,
        tabScopeId: widget.tabScopeId,
        highlightSessionId: widget.highlightSessionId,
        collapsed: _collapsedWorktrees.contains(worktree.path),
        onToggle: () => setState(() {
          if (!_collapsedWorktrees.add(worktree.path)) {
            _collapsedWorktrees.remove(worktree.path);
          }
        }),
      ),
    ];
  }
}

class _ProjectTreeWorktree extends StatefulWidget {
  const _ProjectTreeWorktree({
    required this.group,
    required this.workspace,
    required this.tabScopeId,
    required this.highlightSessionId,
    required this.collapsed,
    required this.onToggle,
  });

  final WorktreeGroup group;
  final Workspace workspace;
  final String tabScopeId;
  final String? highlightSessionId;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  State<_ProjectTreeWorktree> createState() => _ProjectTreeWorktreeState();
}

class _ProjectTreeWorktreeState extends State<_ProjectTreeWorktree> {
  var _hovered = false;
  var _menuOpen = false;

  Future<void> _showContextMenu(
    BuildContext context,
    TapDownDetails details,
    String label,
  ) async {
    final worktree = widget.group.worktree!;
    final workContext = WorkspaceToolsScope.maybeOf(context)?.tools?.context;
    final canRemove =
        !worktree.isMainWorktree &&
        workContext != null &&
        worktreeManagementEnabled(workContext);
    setState(() => _menuOpen = true);
    final selected = await showWorktreeDirectoryContextMenu(
      context,
      tapDetails: details,
      launchPath: worktree.path,
      canRemove: canRemove,
    );
    if (!context.mounted) return;
    setState(() => _menuOpen = false);
    switch (selected) {
      case WorktreeDirectoryMenuAction.newConversation:
        unawaited(
          showWorkspaceComposeLandingWithWorktree(
            context,
            widget.workspace,
            tabScopeId: widget.tabScopeId,
            worktreePath: worktree.path,
          ),
        );
      case WorktreeDirectoryMenuAction.copyPath:
        unawaited(copyWorktreeDirectoryPath(worktree.path));
      case WorktreeDirectoryMenuAction.remove:
        unawaited(
          confirmAndRemoveWorktree(
            context: context,
            group: widget.group,
            workspace: widget.workspace,
            branchLabel: label,
          ),
        );
      case null:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final worktree = widget.group.worktree!;
    final label = widget.group.sidebarLabel ?? worktree.shortBranch;
    final icon = _hovered
        ? widget.collapsed
              ? Icons.chevron_right_rounded
              : Icons.expand_more_rounded
        : Icons.folder_outlined;
    final showRowActions = _hovered || _menuOpen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpHoverRow(
          key: ValueKey('project-tree-worktree-node-${worktree.path}'),
          forceShowTrailing: _menuOpen,
          forceHover: _menuOpen,
          padding: const EdgeInsets.fromLTRB(32, 6, 8, 6),
          hoverColor: workspaceSidebarRowHoverFill(cs),
          onHoverChanged: (hovered) => setState(() => _hovered = hovered),
          onTap: widget.onToggle,
          onSecondaryTapDown: (details) =>
              unawaited(_showContextMenu(context, details, label)),
          trailing: TpIconButton(
            icon: Icons.add_rounded,
            compact: true,
            size: TpIconButton.kCompactSize,
            tooltip: null,
            onTap: () => unawaited(
              showWorkspaceComposeLandingWithWorktree(
                context,
                widget.workspace,
                tabScopeId: widget.tabScopeId,
                worktreePath: worktree.path,
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: Icon(
                    showRowActions
                        ? (widget.collapsed
                              ? Icons.chevron_right_rounded
                              : Icons.expand_more_rounded)
                        : icon,
                    size: context.tpIconSizes.md,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (!widget.collapsed)
          _ProjectTreeSessionList(
            key: ValueKey(
              'project-tree-worktree-session-list-state-${worktree.path}',
            ),
            viewportKey: ValueKey(
              'project-tree-worktree-session-list-${worktree.path}',
            ),
            sessions: widget.group.sessions,
            workspace: widget.workspace,
            tabScopeId: widget.tabScopeId,
            highlightSessionId: widget.highlightSessionId,
            contentLeftInset: 24,
            sessionKeyPrefix: 'project-tree-worktree-session',
          ),
      ],
    );
  }
}

/// Session rows for a project-tree node. The default view keeps a busy
/// worktree compact; expanding it exposes every session through a lazy,
/// fixed-height inner viewport instead of growing the outer sidebar.
class _ProjectTreeSessionList extends StatefulWidget {
  const _ProjectTreeSessionList({
    required this.sessions,
    required this.workspace,
    required this.tabScopeId,
    required this.highlightSessionId,
    required this.contentLeftInset,
    required this.sessionKeyPrefix,
    this.viewportKey,
    super.key,
  });

  final List<AppSession> sessions;
  final Workspace workspace;
  final String tabScopeId;
  final String? highlightSessionId;
  final double contentLeftInset;
  final String sessionKeyPrefix;
  final Key? viewportKey;

  @override
  State<_ProjectTreeSessionList> createState() =>
      _ProjectTreeSessionListState();
}

class _ProjectTreeSessionListState extends State<_ProjectTreeSessionList> {
  bool _showAll = false;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.sessions;
    final overflow = all.length - _projectTreeSessionCollapsedCap;
    final visible = (_showAll || overflow <= 0)
        ? all
        : all.take(_projectTreeSessionCollapsedCap).toList();
    final scrollable = overflow > 0 && _showAll;
    final height =
        math.min(_projectTreeSessionExpandedRowCount, visible.length) *
        _projectTreeSessionRowHeight;
    final outerPosition = Scrollable.maybeOf(context)?.position;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: _showAll && overflow > 0 ? widget.viewportKey : null,
          height: scrollable ? height : null,
          child: ListView.builder(
            controller: _scrollController,
            primary: false,
            padding: EdgeInsets.zero,
            scrollCacheExtent: ScrollCacheExtent.pixels(0),
            physics: scrollable
                ? WorkspaceNestedScrollPhysics(outerPosition: outerPosition)
                : const NeverScrollableScrollPhysics(),
            shrinkWrap: !scrollable,
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final session = visible[index];
              return SidebarSessionTile(
                key: ValueKey(
                  '${widget.sessionKeyPrefix}-${session.sessionId}',
                ),
                session: session,
                highlightSessionId: widget.highlightSessionId,
                contentLeftInset: widget.contentLeftInset,
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
          _ProjectTreeShowMoreRow(
            label: _showAll
                ? context.l10n.worktreeShowLess
                : context.l10n.worktreeMore,
            onTap: () => setState(() => _showAll = !_showAll),
          ),
      ],
    );
  }
}

class _ProjectTreeShowMoreRow extends StatelessWidget {
  const _ProjectTreeShowMoreRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: TpHover(
        onTap: onTap,
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
                label,
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
