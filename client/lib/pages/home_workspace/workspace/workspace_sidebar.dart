import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/layout_cubit.dart';
import '../../../cubits/session_groups_cubit.dart';
import '../../../cubits/shortcut_cubit.dart';
import '../../../cubits/workbench/workbench_cubit.dart';
import '../../../cubits/workbench/workbench_tab.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_session.dart';
import '../../../models/git_worktree.dart';
import '../../../models/session_group.dart';
import '../../../models/workspace.dart';
import '../../../pages/home_workspace/home_workspace_route.dart';
import '../../../services/commands/command_ids.dart';
import '../../../services/commands/command_tooltip.dart';
import '../../../services/commands/key_chord.dart';
import '../../../services/git/git_worktree_service.dart';
import '../../../services/io/local_filesystem.dart';
import '../../../services/storage/app_storage.dart';
import '../../../services/storage/workspace_layout.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import '../../../utils/session/session_project_grouping.dart';
import '../../../utils/session/session_worktree_grouping.dart';
import '../../../utils/workspace/workspace_chrome_profile.dart';
import '../../../widgets/app_toast/app_toast.dart';
import 'session_group_section.dart';
import 'worktree_create_dialog.dart';
import 'worktree_group_section.dart';
import '../../../utils/ui/app_keys.dart';
import '../../../utils/session/app_session_sort.dart';
import '../../../utils/debounce/debounce.dart';
import '../../../utils/session/running_session_ids.dart';
import '../../../utils/session/session_archive_filter.dart';
import '../../../utils/session/session_list_structure.dart';
import '../../../utils/session/session_reorder_merge.dart';
import '../../../utils/session/workspace_sessions.dart';
import '../../../utils/session/workspace_tab_session_scope.dart';
import 'workspace_sidebar_probe.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'workspace_automations_section.dart';
import 'workspace_search_dialog.dart';
import 'workspace_session_actions.dart';

/// Navigates to workspace manage view for [workspace].
void openWorkspaceManagementRoute(BuildContext context, Workspace workspace) {
  try {
    context.read<LayoutCubit>().closeMobileWorkspaceDrawer();
  } on ProviderNotFoundException {
    // Isolated tests may not mount [LayoutCubit].
  }
  final location = GoRouterState.of(context).uri.toString();
  final routeProfile = HomeWorkspaceRoute.profile(location);
  final profileId = workspaceChromeProfileId(
    workspace,
    routeProfileId: routeProfile,
  );
  context.go(
    Uri(
      path: '/home-v2/workspace/${workspace.workspaceId}',
      queryParameters: {'profile': profileId, 'view': 'manage'},
    ).toString(),
  );
}

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
    this.embedFooter = true,
    super.key,
  });

  final Workspace workspace;
  final String tabScopeId;
  final bool embedFooter;

  @override
  State<WorkspaceSidebar> createState() => _WorkspaceSidebarState();
}

class _WorkspaceSidebarState extends State<WorkspaceSidebar> {
  AppSessionSort _sessionSort = AppSessionSort.recentlyUpdated;
  bool _showingArchive = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final toolsContext = WorkspaceToolsScope.maybeOf(context)?.tools?.context;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_showingArchive) ...[
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
            const SizedBox(height: 4),
            Builder(
              builder: (context) {
                context.select<ShortcutCubit, Map<String, List<KeyChord>>>(
                  (c) => c.state.overrides,
                );
                return _SidebarActionTile(
                  key: AppKeys.searchSidebarTile,
                  icon: Icons.search_outlined,
                  label: l10n.workspaceSearchTitle,
                  tooltip: commandTooltip(
                    context,
                    l10n.workspaceSearchTitle,
                    CommandIds.workspaceSearch,
                  ),
                  enabled: true,
                  onTap: throttledTap(
                    'workspace_sidebar_search',
                    () => _openWorkspaceSearch(context),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
          ],
          _RunningSessionsHost(
            workspace: widget.workspace,
            tabScopeId: widget.tabScopeId,
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
            child: Row(
              children: [
                if (_showingArchive) ...[
                  TpIconButton(
                    icon: Icons.arrow_back_rounded,
                    compact: true,
                    size: TpIconButton.kCompactSize,
                    tooltip: l10n.back,
                    onTap: () => setState(() => _showingArchive = false),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    _showingArchive
                        ? l10n.sessionArchiveTitle
                        : l10n.homeWorkspaceConversationsSection,
                    style: TpTextStyles.of(context).mutedSm,
                  ),
                ),
                if (!_showingArchive) ...[
                  _SessionSortButton(
                    sort: _sessionSort,
                    onChanged: (s) => setState(() => _sessionSort = s),
                  ),
                  const SizedBox(width: 2),
                  TpIconButton(
                    icon: Icons.new_label_outlined,
                    compact: true,
                    size: TpIconButton.kCompactSize,
                    tooltip: l10n.sessionGroupCreateTooltip,
                    onTap: throttledTap(
                      'workspace_sidebar_new_group',
                      () => unawaited(_createSessionGroup(context)),
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
                          final repoPath =
                              cubit.state.repoPath.trim().isNotEmpty
                              ? cubit.state.repoPath
                              : widget.workspace.firstFolderPath;
                          unawaited(cubit.load(repoPath, force: true));
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
                  const SizedBox(width: 2),
                  TpIconButton(
                    icon: Icons.archive_outlined,
                    compact: true,
                    size: TpIconButton.kCompactSize,
                    tooltip: l10n.sessionArchiveEntryTooltip,
                    onTap: () => setState(() => _showingArchive = true),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _showingArchive
                ? _ArchivedConversationList(
                    workspace: widget.workspace,
                    tabScopeId: widget.tabScopeId,
                    sessionSort: _sessionSort,
                  )
                : _ConversationListHost(
                    workspace: widget.workspace,
                    tabScopeId: widget.tabScopeId,
                    sessionSort: _sessionSort,
                    onSessionsReordered: _onSessionsReordered,
                  ),
          ),
          if (widget.embedFooter) ...[
            const SizedBox(height: 8),
            Divider(
              height: 1,
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.5),
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
        ],
      ),
    );
  }

  void _openWorkspaceManagement(BuildContext context) {
    openWorkspaceManagementRoute(context, widget.workspace);
  }

  void _openWorkspaceSearch(BuildContext context) {
    unawaited(
      showWorkspaceSearchDialog(
        context,
        workspace: widget.workspace,
        // Same source as the file-tree / git panels; local only before
        // the tools plane has resolved.
        fs:
            WorkspaceToolsScope.maybeOf(context)?.tools?.context.filesystem ??
            LocalFilesystem(),
      ),
    );
  }

  /// Drag always available; dropping stamps [AppSession.sortOrder] and switches
  /// the sidebar to manual order so a time-based re-sort cannot undo the drop.
  void _onSessionsReordered(List<String> orderedSessionIds) {
    if (_sessionSort != AppSessionSort.manual) {
      setState(() => _sessionSort = AppSessionSort.manual);
    }
    unawaited(context.read<ChatCubit>().reorderSessions(orderedSessionIds));
  }

  Future<void> _createSessionGroup(BuildContext context) async {
    final l10n = context.l10n;
    final name = await showTpTextPromptDialog(
      context,
      title: l10n.sessionGroupCreateTitle,
      labelText: l10n.sessionGroupNameLabel,
      confirmLabel: l10n.save,
      cancelLabel: l10n.cancel,
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    context.read<SessionGroupsCubit>().createGroup(name.trim());
  }

  Future<void> _startNewConversation(BuildContext context) async {
    await showWorkspaceComposeLanding(
      context,
      widget.workspace,
      tabScopeId: widget.tabScopeId,
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
      existingWorktreePaths: [for (final wt in cubit.state.worktrees) wt.path],
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
      await cubit.load(repoPath, force: true);
      cubit.setCurrentWorktree(result.worktreePath);
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
}

AppSession? _sessionById(ChatState state, String sessionId) {
  for (final session in state.sessions) {
    if (session.sessionId == sessionId) return session;
  }
  return null;
}

List<AppSession> _sessionsForStructure(
  ChatState state,
  SessionListStructure structure,
  Workspace workspace,
) {
  final byId = {
    for (final session in activeSessions(
      sessionsForWorkspace(workspace, state.sessions),
    ))
      session.sessionId: session,
  };
  return [
    for (final row in structure.rows)
      if (byId[row.sessionId] case final session?) session,
  ];
}

class _RunningSessionsHost extends StatelessWidget {
  const _RunningSessionsHost({
    required this.workspace,
    required this.tabScopeId,
  });

  final Workspace workspace;
  final String tabScopeId;

  List<String> _openSessionTabIds(WorkbenchState workbenchState) => [
    for (final tab in workbenchState.bar(tabScopeId).center.order)
      if (tab.kind == WorkbenchTabKind.session) tab.id,
  ];

  @override
  Widget build(BuildContext context) {
    final workbenchState = context.watch<WorkbenchCubit>().state;
    final running = context.select<ChatCubit, RunningSessionIds>(
      (c) => RunningSessionIds.fromOpenSessionTabs(
        sessions: sessionsForWorkspace(workspace, c.state.sessions),
        openTabSessionIdsInOrder: _openSessionTabIds(workbenchState),
      ),
    );
    return SidebarRebuildProbe(
      key: const Key('workspace-sidebar-running-host-probe'),
      child: running.isEmpty
          ? const SizedBox.shrink()
          : _RunningSessionsSection(
              sessionIds: running.ids,
              workspace: workspace,
              tabScopeId: tabScopeId,
            ),
    );
  }
}

class _ConversationListHost extends StatelessWidget {
  const _ConversationListHost({
    required this.workspace,
    required this.tabScopeId,
    required this.sessionSort,
    required this.onSessionsReordered,
  });

  final Workspace workspace;
  final String tabScopeId;
  final AppSessionSort sessionSort;
  final ValueChanged<List<String>> onSessionsReordered;

  @override
  Widget build(BuildContext context) {
    final structure = context.select<ChatCubit, SessionListStructure>(
      (c) => SessionListStructure.fromSessions(
        activeSessions(sessionsForWorkspace(workspace, c.state.sessions)),
        sort: sessionSort,
      ),
    );
    final sessionsHydrated = context.select<ChatCubit, bool>(
      (c) => c.sessionsLoadedForWorkspace(workspace.workspaceId),
    );
    final wtView = context.select<WorktreeCubit, WorktreeSidebarView>(
      (c) => WorktreeSidebarView.from(c.state),
    );
    final chatState = context.read<ChatCubit>().state;
    final sortedSessions = _sessionsForStructure(
      chatState,
      structure,
      workspace,
    );

    return SidebarRebuildProbe(
      key: const Key('workspace-sidebar-conversation-list-probe'),
      child: _buildWithManualGroups(
        context,
        TpDeferredMountShell(
          delayFrames: 1,
          placeholder: const _SessionListSkeleton(),
          child: _buildBody(
            context,
            sortedSessions,
            structure,
            wtView,
            sessionsHydrated: sessionsHydrated,
          ),
        ),
      ),
    );
  }

  /// Manual group blocks ride ABOVE every automatic layout (flat, worktree-
  /// grouped, multi-project): bounded stack with its own scroll so a
  /// scrollable is never nested inside the list's scrollable.
  Widget _buildWithManualGroups(BuildContext context, Widget listArea) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ManualGroupsHost(
          workspace: workspace,
          tabScopeId: tabScopeId,
          sessionSort: sessionSort,
          highlightSessionId: scopedActiveSessionId(
            context.read<WorkbenchCubit>(),
            tabScopeId,
          ),
        ),
        Expanded(child: listArea),
      ],
    );
  }

  /// Flat session list when the repo has only its main worktree; otherwise a
  /// collapsible worktree-grouped list. The "+ new worktree" header action is
  /// always available regardless of this branch.
  Widget _buildBody(
    BuildContext context,
    List<AppSession> sortedSessions,
    SessionListStructure structure,
    WorktreeSidebarView wtView, {
    required bool sessionsHydrated,
  }) {
    final l10n = context.l10n;
    if (!sessionsHydrated && structure.rows.isEmpty) {
      return const _SessionListSkeleton();
    }
    if (workspace.folders.length > 1) {
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
                projectFolderPath: workspace.firstFolderPath,
                isProjectGroup: true,
              ),
            ],
            wtView,
            workspaceOrderedSessionIds: structure.sessionIds,
            emptyWhenNoSessions: true,
          );
        }
        return structure.rows.isEmpty
            ? _EmptyConversations(label: l10n.homeWorkspaceNoConversations)
            : _buildSessionList(context, structure.sessionIds);
      case WorktreeSessionListLayout.grouped:
        final groups = groupSessionsByWorktree(
          worktrees: wtView.worktrees,
          sessions: sortedSessions,
        );
        return _buildWorktreeGroupList(
          context,
          groups,
          wtView,
          workspaceOrderedSessionIds: structure.sessionIds,
        );
    }
  }

  Widget _buildWorktreeGroupList(
    BuildContext context,
    List<WorktreeGroup> groups,
    WorktreeSidebarView wtView, {
    bool emptyWhenNoSessions = false,
    required List<String> workspaceOrderedSessionIds,
  }) {
    final l10n = context.l10n;
    final hasAnySession = groups.any((g) => g.sessions.isNotEmpty);
    if (emptyWhenNoSessions && !hasAnySession) {
      return _EmptyConversations(label: l10n.homeWorkspaceNoConversations);
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return WorktreeGroupSection(
          key: ValueKey('wt-group-${worktreeGroupCollapseKey(group)}'),
          group: group,
          workspace: workspace,
          tabScopeId: tabScopeId,
          sessionSort: sessionSort,
          workspaceOrderedSessionIds: workspaceOrderedSessionIds,
          onSessionsReordered: onSessionsReordered,
          highlightSessionId: scopedActiveSessionId(
            context.read<WorkbenchCubit>(),
            tabScopeId,
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
      for (final folder in workspace.folders)
        folder.path: cubit.worktreesForProject(folder.path),
    };
    final groups = groupSessionsByWorktreeAcrossProjects(
      folders: workspace.folders,
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
      workspaceOrderedSessionIds: sessionIdsInSortOrder(sortedSessions),
    );
  }

  Widget _buildSessionList(BuildContext context, List<String> sessionIds) {
    return ReorderableListView.builder(
      padding: EdgeInsets.zero,
      buildDefaultDragHandles: false,
      itemCount: sessionIds.length,
      onReorderItem: (oldIndex, newIndex) {
        final ordered = reorderVisibleSessionIds(
          allIds: sessionIds,
          visibleIds: sessionIds,
          oldIndex: oldIndex,
          newIndex: newIndex,
        );
        onSessionsReordered(ordered);
      },
      itemBuilder: (context, index) =>
          _sessionTile(context, sessionIds[index], index: index),
    );
  }

  Widget _sessionTile(
    BuildContext context,
    String sessionId, {
    int index = -1,
  }) {
    final session = _sessionById(context.read<ChatCubit>().state, sessionId);
    if (session == null) return const SizedBox.shrink();
    return SidebarSessionTile(
      key: ValueKey('workspace-sidebar-session-$sessionId'),
      session: session,
      index: index,
      highlightSessionId: scopedActiveSessionId(
        context.read<WorkbenchCubit>(),
        tabScopeId,
      ),
      tapThrottleKeyPrefix: 'workspace_sidebar_session',
      onTap: () => openWorkspaceSessionTab(
        context,
        workspace,
        session,
        tabScopeId: tabScopeId,
      ),
    );
  }
}

class _ArchivedConversationList extends StatelessWidget {
  const _ArchivedConversationList({
    required this.workspace,
    required this.tabScopeId,
    required this.sessionSort,
  });

  final Workspace workspace;
  final String tabScopeId;
  final AppSessionSort sessionSort;

  @override
  Widget build(BuildContext context) {
    final sessions = context.select<ChatCubit, List<AppSession>>(
      (c) => sortAppSessions(
        archivedSessions(sessionsForWorkspace(workspace, c.state.sessions)),
        sort: sessionSort,
      ),
    );
    if (sessions.isEmpty) {
      return _EmptyConversations(label: context.l10n.sessionArchiveEmpty);
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        return SidebarSessionTile(
          key: ValueKey('workspace-archived-session-${session.sessionId}'),
          session: session,
          archiveMode: true,
          highlightSessionId: scopedActiveSessionId(
            context.read<WorkbenchCubit>(),
            tabScopeId,
          ),
          tapThrottleKeyPrefix: 'workspace_archived_session',
          onTap: () => openWorkspaceSessionTab(
            context,
            workspace,
            session,
            tabScopeId: tabScopeId,
          ),
        );
      },
    );
  }
}

class _RunningSessionsSection extends StatelessWidget {
  const _RunningSessionsSection({
    required this.sessionIds,
    required this.workspace,
    required this.tabScopeId,
  });

  final List<String> sessionIds;
  final Workspace workspace;
  final String tabScopeId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final chatState = context.read<ChatCubit>().state;
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
        for (final sessionId in sessionIds)
          if (_sessionById(chatState, sessionId) case final session?)
            SidebarSessionTile(
              key: ValueKey('workspace-running-session-$sessionId'),
              session: session,
              highlightSessionId: scopedActiveSessionId(
                context.read<WorkbenchCubit>(),
                tabScopeId,
              ),
              tapThrottleKeyPrefix: 'workspace_running_session',
              onTap: () => openWorkspaceSessionTab(
                context,
                workspace,
                session,
                tabScopeId: tabScopeId,
              ),
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
    this.tooltip,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final String? tooltip;

  @override
  State<_SidebarActionTile> createState() => _SidebarActionTileState();
}

class _SidebarActionTileState extends State<_SidebarActionTile> {
  bool get _enabled => widget.enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final foreground = _enabled
        ? cs.onSurface
        : cs.onSurface.withValues(alpha: 0.38);

    final tile = TpHover(
      enabled: _enabled,
      onTap: widget.onTap,
      hoverColor: cs.onSurface.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          Icon(widget.icon, size: context.tpIconSizes.md, color: foreground),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.label, style: styles.lg)),
        ],
      ),
    );

    final tip = widget.tooltip;
    if (tip == null || tip.isEmpty) return tile;
    return Tooltip(message: tip, child: tile);
  }
}

class _SessionSortButton extends StatelessWidget {
  const _SessionSortButton({required this.sort, required this.onChanged});

  final AppSessionSort sort;
  final ValueChanged<AppSessionSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpActionMenuIconAnchor(
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
            TpActionMenuItem(
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

/// Renders one [SessionGroupSection] per manual group, bounded to a fixed
/// maxHeight with its own scroll so several expanded blocks cannot overflow
/// the column. Hidden entirely when the workspace has no groups.
class _ManualGroupsHost extends StatelessWidget {
  const _ManualGroupsHost({
    required this.workspace,
    required this.tabScopeId,
    required this.sessionSort,
    required this.highlightSessionId,
  });

  final Workspace workspace;
  final String tabScopeId;
  final AppSessionSort sessionSort;
  final String? highlightSessionId;

  @override
  Widget build(BuildContext context) {
    final groups = context.select<SessionGroupsCubit, List<SessionGroup>>(
      (c) => c.state.ready ? c.state.groups : const <SessionGroup>[],
    );
    if (groups.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final group in groups)
              SessionGroupSection(
                key: ValueKey('manual-group-${group.id}'),
                group: group,
                workspace: workspace,
                tabScopeId: tabScopeId,
                sessionSort: sessionSort,
                highlightSessionId: highlightSessionId,
              ),
          ],
        ),
      ),
    );
  }
}
