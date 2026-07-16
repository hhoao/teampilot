import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_session.dart';
import '../../../models/git_worktree.dart';
import '../../../models/workspace.dart';
import '../../../pages/home_workspace/home_workspace_route.dart';
import '../../../services/git/git_worktree_service.dart';
import '../../../services/storage/app_storage.dart';
import '../../../services/storage/workspace_layout.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import '../../../utils/session/session_project_grouping.dart';
import '../../../utils/session/session_worktree_grouping.dart';
import '../../../utils/workspace/workspace_chrome_profile.dart';
import '../../../widgets/app_toast/app_toast.dart';
import 'worktree_create_dialog.dart';
import 'worktree_group_section.dart';
import '../../../utils/ui/app_keys.dart';
import '../../../utils/session/app_session_sort.dart';
import '../../../utils/debounce/debounce.dart';
import '../../../utils/session/session_reorder_merge.dart';
import '../../../utils/session/workspace_running_sessions.dart';
import '../../../utils/session/workspace_sidebar_sessions.dart';
import '../../../utils/session/workspace_tab_session_scope.dart';
import '../../../widgets/menu/sidebar_action_menu.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'workspace_automations_section.dart';
import 'workspace_search_dialog.dart';
import 'workspace_session_actions.dart';

/// Shared resize limits for [WorkspaceSidebar].
class WorkspaceSidebarLayout {
  const WorkspaceSidebarLayout._();

  static const double defaultWidth = 280;
  static const double minWidth = 220;
  static const double maxWidth = 480;
}

/// Workspace conversation sidebar.
class WorkspaceSidebar extends StatefulWidget {
  const WorkspaceSidebar({
    required this.workspace,
    required this.tabScopeId,
    super.key,
  });

  final Workspace workspace;
  final String tabScopeId;

  @override
  State<WorkspaceSidebar> createState() => _WorkspaceSidebarState();
}

class _WorkspaceSidebarState extends State<WorkspaceSidebar> {
  AppSessionSort _sessionSort = AppSessionSort.recentlyUpdated;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sessionSnapshot = context.select<ChatCubit, WorkspaceSidebarSessions>(
      (c) => WorkspaceSidebarSessions.forWorkspace(
        allSessions: c.state.sessions,
        workspace: widget.workspace,
      ),
    );
    final sortedSessions = sortAppSessions(
      sessionSnapshot.sessions,
      sort: _sessionSort,
    );
    final sessionsHydrated = context.select<ChatCubit, bool>(
      (c) => c.sessionsLoadedForWorkspace(widget.workspace.workspaceId),
    );
    final wtView = context.select<WorktreeCubit, WorktreeSidebarView>(
      (c) => WorktreeSidebarView.from(c.state),
    );
    final toolsContext = WorkspaceToolsScope.maybeOf(context)?.tools?.context;
    // Must read c.state.sessions inside the selector so working-id updates never
    // resolve against a stale filtered list from a prior build closure.
    final runningSessionIds = context.select<ChatCubit, List<String>>((c) {
      final sessions = WorkspaceSidebarSessions.forWorkspace(
        allSessions: c.state.sessions,
        workspace: widget.workspace,
      ).sessions;
      final working = c.state.workingSessionIds;
      final runningTabIds = c.tabStore
          .tabsForWorkspace(widget.tabScopeId)
          .where((tab) => tab.isRunning)
          .map((tab) => tab.info.id);
      return workspaceRunningSessions(
        sessions: sessions,
        workingSessionIds: working,
        openTabSessionIds: openTabSessionIdsForWorkspace(runningTabIds),
      ).map((s) => s.sessionId).toList();
    });
    final sortedById = {for (final s in sortedSessions) s.sessionId: s};
    final runningSessions = [
      for (final id in runningSessionIds)
        if (sortedById[id] case final session?) session,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceAutomationsSection(workspace: widget.workspace),
          const SizedBox(height: 12),
          _SidebarActionTile(
            key: AppKeys.newChatSidebarTile,
            icon: Icons.edit_outlined,
            label: l10n.homeWorkspaceNewConversation,
            enabled: true,
            onTap: throttledAsync(
              'workspace_sidebar_new_chat',
              () => _startNewConversation(context),
            ),
          ),
          if (runningSessions.isNotEmpty) ...[
            const SizedBox(height: 14),
            _RunningSessionsSection(
              sessions: runningSessions,
              workspace: widget.workspace,
              tabScopeId: widget.tabScopeId,
            ),
          ],
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.homeWorkspaceConversationsSection,
                    style: TpTextStyles.of(context).mutedSm,
                  ),
                ),
                _SessionSortButton(
                  sort: _sessionSort,
                  onChanged: (s) => setState(() => _sessionSort = s),
                ),
                const SizedBox(width: 2),
                TpIconButton(
                  icon: Icons.search_rounded,
                  compact: true,
                  size: TpIconButton.kCompactSize,
                  tooltip: l10n.workspaceSearchTitle,
                  onTap: throttledTap(
                    'workspace_sidebar_search',
                    () => unawaited(
                      showWorkspaceSearchDialog(
                        context,
                        workspace: widget.workspace,
                      ),
                    ),
                  ),
                ),
                if (toolsContext != null &&
                    worktreeManagementEnabled(toolsContext)) ...[
                  const SizedBox(width: 2),
                  TpIconButton(
                    icon: Icons.refresh_rounded,
                    compact: true,
                    size: TpIconButton.kCompactSize,
                    tooltip: l10n.worktreeRefreshTooltip,
                    onTap: throttledTap(
                      'workspace_sidebar_refresh_worktrees',
                      () {
                        final cubit = context.read<WorktreeCubit>();
                        final repoPath = cubit.state.repoPath.trim().isNotEmpty
                            ? cubit.state.repoPath
                            : widget.workspace.firstFolderPath;
                        unawaited(cubit.load(repoPath));
                      },
                    ),
                  ),
                  const SizedBox(width: 2),
                  TpIconButton(
                    icon: Icons.account_tree_outlined,
                    compact: true,
                    size: TpIconButton.kCompactSize,
                    tooltip: l10n.worktreeNewWorktreeTooltip,
                    onTap: throttledTap(
                      'workspace_sidebar_new_worktree',
                      () => unawaited(_createWorktree(context)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _buildBody(
              context,
              sortedSessions,
              wtView,
              sessionsHydrated: sessionsHydrated,
            ),
          ),
          const SizedBox(height: 8),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant
                .withValues(alpha: 0.5),
          ),
          const SizedBox(height: 4),
          _SidebarActionTile(
            key: AppKeys.homeWorkspaceWorkspaceManagementTile,
            icon: Icons.tune_outlined,
            label: l10n.homeWorkspaceWorkspaceManagement,
            onTap: throttledTap(
              'workspace_sidebar_manage',
              () => _openWorkspaceManagement(context),
            ),
          ),
        ],
      ),
    );
  }

  void _openWorkspaceManagement(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final routeProfile = HomeWorkspaceRoute.profile(location);
    final profileId = workspaceChromeProfileId(
      widget.workspace,
      routeProfileId: routeProfile,
    );
    context.go(
      Uri(
        path: '/home-v2/workspace/${widget.workspace.workspaceId}',
        queryParameters: {
          'profile': profileId,
          'view': 'manage',
        },
      ).toString(),
    );
  }

  /// Flat session list when the repo has only its main worktree; otherwise a
  /// collapsible worktree-grouped list. The "+ new worktree" header action is
  /// always available regardless of this branch.
  Widget _buildBody(
    BuildContext context,
    List<AppSession> sortedSessions,
    WorktreeSidebarView wtView, {
    required bool sessionsHydrated,
  }) {
    final l10n = context.l10n;
    // Sessions still loading from disk/SFTP: show the skeleton rather than the
    // empty-conversations placeholder, so a cold tab switch never flashes
    // "no conversations" before the list pops in.
    if (!sessionsHydrated && sortedSessions.isEmpty) {
      return const _SessionListSkeleton();
    }
    if (widget.workspace.folders.length > 1) {
      return _buildMultiProjectWorktreeGroupedList(
        context,
        sortedSessions,
        wtView,
      );
    }
    switch (wtView.sessionListLayout) {
      case WorktreeSessionListLayout.indeterminate:
        return const _SessionListSkeleton();
      case WorktreeSessionListLayout.flat:
        if (!wtView.loading && wtView.worktrees.isEmpty) {
          return _buildWorktreeGroupList(
            context,
            [
              WorktreeGroup(
                worktree: null,
                sessions: sortedSessions,
                projectFolderPath: widget.workspace.firstFolderPath,
                isProjectGroup: true,
              ),
            ],
            wtView,
            sortedSessions: sortedSessions,
            emptyWhenNoSessions: true,
          );
        }
        return sortedSessions.isEmpty
            ? _EmptyConversations(label: l10n.homeWorkspaceNoConversations)
            : _buildSessionList(context, sortedSessions);
      case WorktreeSessionListLayout.grouped:
        final groups = groupSessionsByWorktree(
          worktrees: wtView.worktrees,
          sessions: sortedSessions,
        );
        return _buildWorktreeGroupList(
          context,
          groups,
          wtView,
          sortedSessions: sortedSessions,
        );
    }
  }

  Widget _buildWorktreeGroupList(
    BuildContext context,
    List<WorktreeGroup> groups,
    WorktreeSidebarView wtView, {
    bool emptyWhenNoSessions = false,
    required List<AppSession> sortedSessions,
  }) {
    final l10n = context.l10n;
    final hasAnySession = groups.any((g) => g.sessions.isNotEmpty);
    if (emptyWhenNoSessions && !hasAnySession) {
      return _EmptyConversations(label: l10n.homeWorkspaceNoConversations);
    }
    final workspaceOrderedSessionIds = sessionIdsInSortOrder(sortedSessions);
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return WorktreeGroupSection(
          key: ValueKey('wt-group-${worktreeGroupCollapseKey(group)}'),
          group: group,
          workspace: widget.workspace,
          tabScopeId: widget.tabScopeId,
          sessionSort: _sessionSort,
          workspaceOrderedSessionIds: workspaceOrderedSessionIds,
          onSessionsReordered: _onSessionsReordered,
          highlightSessionId: scopedActiveSessionId(
            context.read<ChatCubit>(),
            widget.tabScopeId,
          ),
          collapsed: wtView.collapsed.contains(worktreeGroupCollapseKey(group)),
        );
      },
    );
  }

  Widget _buildMultiProjectWorktreeGroupedList(
    BuildContext context,
    List<AppSession> sortedSessions,
    WorktreeSidebarView wtView,
  ) {
    final l10n = context.l10n;
    final cubit = context.read<WorktreeCubit>();
    final worktreesByProject = <String, List<GitWorktree>>{
      for (final folder in widget.workspace.folders)
        folder.path: cubit.worktreesForProject(folder.path),
    };
    final groups = groupSessionsByWorktreeAcrossProjects(
      folders: widget.workspace.folders,
      worktreesByProjectPath: worktreesByProject,
      sessions: sortedSessions,
    );
    final hasAnySession = groups.any((g) => g.sessions.isNotEmpty);
    if (!hasAnySession && sortedSessions.isEmpty) {
      return _EmptyConversations(label: l10n.homeWorkspaceNoConversations);
    }
    return _buildWorktreeGroupList(
      context,
      groups,
      wtView,
      sortedSessions: sortedSessions,
    );
  }

  Future<void> _createWorktree(BuildContext context) async {
    final cubit = context.read<WorktreeCubit>();
    final l10n = context.l10n;
    final tools = WorkspaceToolsScope.of(context).tools;
    if (tools == null) return;
    final repoPath =
        context.read<WorktreeCubit>().state.repoPath.trim().isNotEmpty
        ? context.read<WorktreeCubit>().state.repoPath
        : widget.workspace.firstFolderPath;
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final result = await showWorktreeCreateDialog(
      context,
      repoName: _basename(repoPath),
      repoPath: repoPath,
      layout: layout.worktreePathFor,
      branchLoader: branchListLoaderFor(tools.context),
      showStartConversationOption: true,
    );
    if (result == null) return;
    try {
      await GitWorktreeService.forContext(tools.context).add(
        repoPath,
        result.worktreePath,
        branch: result.branch,
        baseRef: result.baseRef,
        existingBranch: result.existingBranch,
      );
      await cubit.load(repoPath);
      cubit.setCurrentWorktree(result.worktreePath);
      if (result.startConversation && context.mounted) {
        await showWorkspaceComposeLandingWithWorktree(
          context,
          widget.workspace,
          tabScopeId: widget.tabScopeId,
          worktreePath: result.worktreePath,
        );
      }
    } on Object catch (error) {
      if (!context.mounted) return;
      AppToast.show(
        context,
        message: l10n.worktreeCreateFailed(error.toString()),
        variant: TpToastVariant.error,
      );
    }
  }

  static String _basename(String path) {
    final parts = path.replaceAll(r'\', '/').split('/')
      ..removeWhere((e) => e.isEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  /// Drag always available; dropping stamps [AppSession.sortOrder] and switches
  /// the sidebar to manual order so a time-based re-sort cannot undo the drop.
  void _onSessionsReordered(List<String> orderedSessionIds) {
    if (_sessionSort != AppSessionSort.manual) {
      setState(() => _sessionSort = AppSessionSort.manual);
    }
    unawaited(context.read<ChatCubit>().reorderSessions(orderedSessionIds));
  }

  Widget _buildSessionList(BuildContext context, List<AppSession> sessions) {
    return ReorderableListView.builder(
      padding: EdgeInsets.zero,
      buildDefaultDragHandles: false,
      itemCount: sessions.length,
      onReorderItem: (oldIndex, newIndex) {
        final ordered = reorderVisibleSessionIds(
          allIds: [for (final s in sessions) s.sessionId],
          visibleIds: [for (final s in sessions) s.sessionId],
          oldIndex: oldIndex,
          newIndex: newIndex,
        );
        _onSessionsReordered(ordered);
      },
      itemBuilder: (context, index) =>
          _sessionTile(context, sessions[index], index: index),
    );
  }

  Widget _sessionTile(
    BuildContext context,
    AppSession session, {
    int index = -1,
  }) {
    return SidebarSessionTile(
      key: ValueKey('workspace-sidebar-session-${session.sessionId}'),
      session: session,
      index: index,
      highlightSessionId: scopedActiveSessionId(
        context.read<ChatCubit>(),
        widget.tabScopeId,
      ),
      tapThrottleKeyPrefix: 'workspace_sidebar_session',
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
  }

  Future<void> _startNewConversation(BuildContext context) async {
    await showWorkspaceComposeLanding(
      context,
      widget.workspace,
      tabScopeId: widget.tabScopeId,
    );
  }
}

class _RunningSessionsSection extends StatelessWidget {
  const _RunningSessionsSection({
    required this.sessions,
    required this.workspace,
    required this.tabScopeId,
  });

  final List<AppSession> sessions;
  final Workspace workspace;
  final String tabScopeId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
          child: Text(
            l10n.workspaceRunningSessionsSection,
            style: TpTextStyles.of(context).mutedSm,
          ),
        ),
        for (final session in sessions)
          SidebarSessionTile(
            key: ValueKey('workspace-running-session-${session.sessionId}'),
            session: session,
            highlightSessionId: scopedActiveSessionId(
              context.read<ChatCubit>(),
              tabScopeId,
            ),
            tapThrottleKeyPrefix: 'workspace_running_session',
            onTap: () {
              unawaited(
                openWorkspaceSessionTab(
                  context,
                  workspace,
                  session,
                  tabScopeId: tabScopeId,
                ),
              );
            },
          ),
      ],
    );
  }
}

class _SidebarActionTile extends StatefulWidget {
  const _SidebarActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.disabledTooltip,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final String? disabledTooltip;

  @override
  State<_SidebarActionTile> createState() => _SidebarActionTileState();
}

class _SidebarActionTileState extends State<_SidebarActionTile> {
  bool _hovered = false;

  bool get _enabled => widget.enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final background = !_enabled
        ? Colors.transparent
        : _hovered
        ? cs.onSurface.withValues(alpha: 0.05)
        : Colors.transparent;
    final foreground = _enabled
        ? cs.onSurface
        : cs.onSurface.withValues(alpha: 0.38);

    final tile = MouseRegion(
      onEnter: _enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: _enabled ? (_) => setState(() => _hovered = false) : null,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _enabled ? widget.onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: context.tpIconSizes.md,
                  color: foreground,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.label, style: styles.lg)),
              ],
            ),
          ),
        ),
      ),
    );

    if (!_enabled && widget.disabledTooltip != null) {
      return Tooltip(message: widget.disabledTooltip!, child: tile);
    }
    return tile;
  }
}

class _SessionSortButton extends StatelessWidget {
  const _SessionSortButton({required this.sort, required this.onChanged});

  final AppSessionSort sort;
  final ValueChanged<AppSessionSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SidebarActionMenuIconAnchor(
      size: TpIconButton.kCompactSize,
      triggerBuilder: (context, controller) => TpIconButton(
        icon: Icons.sort_rounded,
        compact: true,
        size: TpIconButton.kCompactSize,
        tooltip: l10n.sessionSortTooltip,
        onTap: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
      buildMenuChildren: (context, controller) {
        return [
          for (final value in AppSessionSort.menuValues)
            SidebarActionMenuItem(
              icon: _iconForSessionSort(value),
              label: _labelForSessionSort(value, l10n),
              trailing: sort == value
                  ? Icon(
                      Icons.check,
                      size: context.tpIconSizes.md,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    )
                  : null,
              menuController: controller,
              onTap: () => onChanged(value),
            ),
        ];
      },
    );
  }

  static String _labelForSessionSort(
    AppSessionSort sort,
    AppLocalizations l10n,
  ) => switch (sort) {
    AppSessionSort.manual => l10n.sessionSortRecentlyUpdated,
    AppSessionSort.recentlyUpdated => l10n.sessionSortRecentlyUpdated,
    AppSessionSort.createdDesc => l10n.sessionSortCreatedDesc,
  };

  static IconData _iconForSessionSort(AppSessionSort sort) => switch (sort) {
    AppSessionSort.manual => Icons.update_rounded,
    AppSessionSort.recentlyUpdated => Icons.update_rounded,
    AppSessionSort.createdDesc => Icons.event_rounded,
  };
}

class _EmptyConversations extends StatelessWidget {
  const _EmptyConversations({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.forum_outlined,
              size: context.tpIconSizes.md,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: styles.smColored(cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder while the git worktree list for this workspace is still loading.
/// Avoids briefly showing a flat session list that immediately regroups.
class _SessionListSkeleton extends StatefulWidget {
  const _SessionListSkeleton();

  @override
  State<_SessionListSkeleton> createState() => _SessionListSkeletonState();
}

class _SessionListSkeletonState extends State<_SessionListSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.onSurface.withValues(alpha: 0.06);
    final highlight = cs.onSurface.withValues(alpha: 0.16);
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final widthFactor = switch (index % 3) {
          0 => 0.92,
          1 => 0.74,
          _ => 0.58,
        };
        return LayoutBuilder(
          builder: (context, constraints) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Container(
                height: 34,
                width: constraints.maxWidth * widthFactor,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    colors: [base, highlight, base],
                    stops: const [0.1, 0.5, 0.9],
                    transform: _ShimmerSlide(_controller.value),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Slides the shimmer highlight band across a bar as the controller advances.
class _ShimmerSlide extends GradientTransform {
  const _ShimmerSlide(this.t);

  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (3.0 * t - 1.5), 0, 0);
}
