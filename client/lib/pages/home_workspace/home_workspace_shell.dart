import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/workspace_tools_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../models/workspace_tab_ref.dart';
import '../../models/workspace_topology.dart';
import '../../models/home_closed_workspace_entry.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/workspace_display_name.dart';
import '../../services/home_workspace/home_closed_workspaces_store.dart';
import '../../services/home_workspace/home_open_workspaces_store.dart';
import '../../services/home_workspace/home_recent_workspaces_store.dart';
import '../../services/home_workspace/home_workspace_ui_cache.dart';
import '../../services/file_tree/workspace_file_tree_store.dart';
import '../../services/workspace/workspace_tools_scope_registry.dart';
import '../../services/workspace/workspace_worktree_registry.dart';
import '../../services/terminal/workspace_terminal_registry.dart';
import '../../widgets/app_dialog.dart';
import 'home_workspace_body_stack.dart';
import 'home_workspace_tab_scope.dart';
import 'home_workspace_title_bar.dart';
import 'open_workspace_tab_actions.dart';

/// Persistent chrome for the workspace-home route family.
class HomeShell extends StatefulWidget {
  const HomeShell({required this.location, super.key});

  final String location;

  @override
  State<HomeShell> createState() => _HomeShellState();

  @visibleForTesting
  static List<WorkspaceTabRef> mergeOpenTabs({
    required List<WorkspaceTabRef> persisted,
    required WorkspaceTabRef? routeTab,
  }) {
    final merged = <WorkspaceTabRef>[];
    void add(WorkspaceTabRef tab) {
      if (tab.workspaceId.trim().isEmpty) return;
      if (merged.any((e) => e.tabKey == tab.tabKey)) return;
      merged.add(tab);
    }

    for (final tab in persisted) {
      add(tab);
    }
    if (routeTab != null) add(routeTab);
    return merged;
  }
}

class _HomeShellState extends State<HomeShell> {
  final _recentWorkspacesStore = HomeRecentWorkspacesStore();
  final _closedWorkspacesStore = HomeClosedWorkspacesStore();
  final _openWorkspacesStore = HomeOpenWorkspacesStore();

  late List<WorkspaceTabRef> _openTabs;
  List<HomeClosedWorkspaceEntry> _recentlyClosed = const [];

  @override
  void initState() {
    super.initState();
    final cache = context.read<HomeWorkspaceUiCache>();
    final routeTab = WorkspaceTabRef.fromLocation(widget.location);
    _openTabs = HomeShell.mergeOpenTabs(
      persisted: cache.openWorkspaceTabs,
      routeTab: routeTab,
    );
    unawaited(_finishOpenTabsBootstrap(routeTab));
    if (routeTab == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncTeamSessionScope(context);
      });
    }
  }

  Future<void> _finishOpenTabsBootstrap(WorkspaceTabRef? routeTab) async {
    if (routeTab != null) {
      unawaited(_recentWorkspacesStore.recordVisit(routeTab));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<LayoutCubit>().setLastOpenedWorkspaceId(
          routeTab.workspaceId,
        );
      });
    }
    await _persistOpenTabs();
    await _reloadRecentlyClosed();
    for (final tab in _openTabs) {
      _prefetchWorkspaceSessions(tab.workspaceId);
    }
  }

  void _prefetchWorkspaceSessions(String workspaceId) {
    if (!mounted || workspaceId.trim().isEmpty) return;
    unawaited(
      context.read<ChatCubit>().ensureSessionsForWorkspace(workspaceId),
    );
  }

  Future<void> _persistOpenTabs() async {
    await _openWorkspacesStore.saveOrderedTabs(_openTabs);
  }

  Future<void> _reloadRecentlyClosed() async {
    final all = await _closedWorkspacesStore.load();
    if (!mounted) return;
    final open = _openTabs.map((t) => t.tabKey).toSet();
    setState(
      () => _recentlyClosed = [
        for (final e in all)
          if (!open.contains(e.tabKey)) e,
      ],
    );
  }

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      final routeTab = WorkspaceTabRef.fromLocation(widget.location);
      if (routeTab != null) {
        if (!_openTabs.any((t) => t.tabKey == routeTab.tabKey)) {
          setState(() => _openTabs = [..._openTabs, routeTab]);
          unawaited(_persistOpenTabs());
        }
        unawaited(_recentWorkspacesStore.recordVisit(routeTab));
        context.read<LayoutCubit>().setLastOpenedWorkspaceId(
          routeTab.workspaceId,
        );
      } else {
        _syncTeamSessionScope(context);
      }
    }
  }

  void _selectTab(WorkspaceTabRef tab) => context.go(tab.route);

  void _goHome() => context.go('/home-v2');

  void _openTab(WorkspaceTabRef tab, {required bool activate}) {
    if (!_openTabs.any((t) => t.tabKey == tab.tabKey)) {
      setState(() => _openTabs = [..._openTabs, tab]);
      unawaited(_persistOpenTabs());
    }
    unawaited(_recentWorkspacesStore.recordVisit(tab));
    _prefetchWorkspaceSessions(tab.workspaceId);
    if (activate) {
      _selectTab(tab);
    }
  }

  void _openWorkspace(String workspaceId, {required bool activate}) {
    _openTab(WorkspaceTabRef(workspaceId: workspaceId), activate: activate);
  }

  Future<void> _reopenClosedTab(String tabKey) async {
    final entry = _recentlyClosed.where((e) => e.tabKey == tabKey).firstOrNull;
    if (entry == null) return;
    await _closedWorkspacesStore.remove(tabKey);
    if (!mounted) return;
    _openTab(WorkspaceTabRef(workspaceId: entry.workspaceId), activate: true);
    await _reloadRecentlyClosed();
  }

  Future<void> _closeTab(String tabKey) async {
    final tab = _openTabs.where((t) => t.tabKey == tabKey).firstOrNull;
    if (tab == null) return;
    final workspaces = context.read<ChatCubit>().state.workspaces;
    final workspace = _resolve(workspaces, tab.workspaceId);
    final chat = context.read<ChatCubit>();
    final terminalRegistry = context.read<WorkspaceTerminalRegistry>();
    final workspaceTools = context.read<WorkspaceToolsCubit>();
    final running = chat.openTabCountForWorkspace(tab.tabKey);
    if (running > 0) {
      final confirmed = await _confirmCloseWithSessions(running);
      if (confirmed != true || !mounted) return;
      chat.closeTabsForWorkspace(tab.tabKey);
    }
    final idx = _openTabs.indexWhere((t) => t.tabKey == tabKey);
    if (idx < 0) return;
    await _closedWorkspacesStore.recordClosed(
      HomeClosedWorkspaceEntry.fromTab(
        tab,
        displayName: workspace?.effectiveDisplay ?? tab.workspaceId,
        primaryPath: workspace?.firstFolderPath ?? '',
        topology: workspace == null
            ? null
            : workspaceTopologyOf(workspace.folders),
      ),
    );
    if (!mounted) return;
    final activeTab = WorkspaceTabRef.fromLocation(widget.location);
    final wasActive = activeTab?.tabKey == tabKey;
    final next = [..._openTabs]..removeAt(idx);
    setState(() => _openTabs = next);
    await _persistOpenTabs();
    await _reloadRecentlyClosed();
    if (!mounted) return;

    terminalRegistry.disposeWorkspace(tab.tabKey);
    workspaceTools.removeWorkspace(tab.tabKey);
    context.read<WorkspaceToolsScopeRegistry>().removeScope(tab.tabKey);

    context.read<WorkspaceFileTreeStore>().removeWorkspace(tab.workspaceId);
    context.read<WorkspaceWorktreeRegistry>().removeWorkspace(tab.workspaceId);

    if (running == 0) {
      chat.closeTabsForWorkspace(tab.tabKey);
    }
    if (wasActive) {
      final candidates = [
        for (final candidate in next)
          if (_resolve(workspaces, candidate.workspaceId) != null) candidate,
      ];
      if (candidates.isEmpty) {
        _goHome();
      } else {
        final target = candidates[idx.clamp(0, candidates.length - 1)];
        _selectTab(target);
      }
    }
  }

  Future<bool?> _confirmCloseWithSessions(int running) {
    final l10n = context.l10n;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(
              title: l10n.homeWorkspaceCloseWorkspaceTitle,
              onClose: () => Navigator.of(dialogContext).pop(false),
            ),
            const SizedBox(height: 16),
            Text(l10n.homeWorkspaceCloseWorkspaceMessage(running)),
            AppDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(l10n.homeWorkspaceCloseWorkspaceConfirm),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _syncTeamSessionScope(BuildContext context) {
    final scopeOn = context
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .scopeSessionsToSelectedTeam;
    final selectedTeam = context.read<LaunchProfileCubit>().state.selectedTeam;
    context.read<ChatCubit>().setTeamSessionScope(
      scopeSessionsToSelectedTeam: scopeOn,
      selectedTeamId: selectedTeam?.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SessionPreferencesCubit, SessionPreferencesState>(
      listenWhen: (previous, next) =>
          previous.preferences.scopeSessionsToSelectedTeam !=
          next.preferences.scopeSessionsToSelectedTeam,
      listener: (context, _) => _syncTeamSessionScope(context),
      child: BlocListener<LaunchProfileCubit, LaunchProfileState>(
        listenWhen: (previous, next) =>
            previous.selectedTeam?.id != next.selectedTeam?.id,
        listener: (context, _) => _syncTeamSessionScope(context),
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.workspacePageChrome(
            WorkspaceTabRef.fromLocation(widget.location) == null
                ? WorkspacePageChrome.home
                : WorkspacePageChrome.workspace,
          ),
          body: Column(
            children: [
              _HomeShellTitleBar(
                location: widget.location,
                openTabs: _openTabs,
                recentlyClosed: _recentlyClosed,
                onHomeTap: _goHome,
                onSelectTab: (tabKey) {
                  final tab = _openTabs
                      .where((t) => t.tabKey == tabKey)
                      .firstOrNull;
                  if (tab != null) _selectTab(tab);
                },
                onCloseTab: (tabKey) => unawaited(_closeTab(tabKey)),
                onReopenClosedTab: (tabKey) =>
                    unawaited(_reopenClosedTab(tabKey)),
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: HomeTabScope(
                    openWorkspace: (id, {activate = true}) =>
                        _openWorkspace(id, activate: activate),
                    child: HomeWorkspaceBodyStack(
                      location: widget.location,
                      openTabs: _openTabs,
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

  static Workspace? _resolve(List<Workspace> workspaces, String id) {
    for (final p in workspaces) {
      if (p.workspaceId == id) return p;
    }
    return null;
  }
}

class _HomeShellTitleBar extends StatelessWidget {
  const _HomeShellTitleBar({
    required this.location,
    required this.openTabs,
    required this.recentlyClosed,
    required this.onHomeTap,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onReopenClosedTab,
  });

  final String location;
  final List<WorkspaceTabRef> openTabs;
  final List<HomeClosedWorkspaceEntry> recentlyClosed;
  final VoidCallback onHomeTap;
  final ValueChanged<String> onSelectTab;
  final ValueChanged<String> onCloseTab;
  final ValueChanged<String> onReopenClosedTab;

  @override
  Widget build(BuildContext context) {
    final activeTab = WorkspaceTabRef.fromLocation(location);
    final pageChrome = activeTab == null
        ? WorkspacePageChrome.home
        : WorkspacePageChrome.workspace;
    final openWorkspaceIds = openTabs.map((t) => t.workspaceId).toSet();
    final workspaces = context.select<ChatCubit, List<Workspace>>((c) {
      return c.state.workspaces;
    });
    final openWorkspaces = [
      for (final workspace in workspaces)
        if (openWorkspaceIds.contains(workspace.workspaceId)) workspace,
    ];
    final l10n = context.l10n;
    final tabs = <HomeWorkspaceTab>[
      for (final tab in openTabs)
        if (_HomeShellState._resolve(openWorkspaces, tab.workspaceId)
            case final workspace?)
          _workspaceTab(tab: tab, workspace: workspace, l10n: l10n),
    ];

    return HomeTitleBar(
      tabs: tabs,
      activeTabKey: activeTab?.tabKey,
      pageChrome: pageChrome,
      recentlyClosed: recentlyClosed,
      workspaces: workspaces,
      onHomeTap: onHomeTap,
      onSelectTab: onSelectTab,
      onCloseTab: onCloseTab,
      onReopenClosedTab: onReopenClosedTab,
    );
  }

  HomeWorkspaceTab _workspaceTab({
    required WorkspaceTabRef tab,
    required Workspace workspace,
    required AppLocalizations l10n,
  }) {
    final workspaceName = workspace.localizedName(l10n);
    final topology = workspaceTopologyOf(workspace.folders);
    return HomeWorkspaceTab(
      id: tab.tabKey,
      name: workspaceName,
      topology: topology,
      tooltip: formatWorkspaceTabTooltip(
        workspace: workspace,
        displayName: workspaceName,
        topology: topology,
        topologyLabel: workspaceTopologyLabel(l10n, topology),
      ),
      closable: true,
    );
  }
}
