import 'dart:async';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../cubits/chat_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/run_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workspace_tools_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/home_closed_workspace_entry.dart';
import '../../models/workspace.dart';
import '../../models/workspace_tab_ref.dart';
import '../../models/workspace_topology.dart';
import '../../services/commands/command_bus.dart';
import '../../services/commands/command_ids.dart';
import '../../services/file_tree/workspace_file_tree_store.dart';
import '../../services/floating_workspace/floating_maximize_insets.dart';
import '../../services/home_workspace/home_closed_workspaces_store.dart';
import '../../services/home_workspace/home_open_workspaces_store.dart';
import '../../services/home_workspace/home_recent_workspaces_store.dart';
import '../../services/home_workspace/home_workspace_ui_cache.dart';
import '../../services/run/launch_adapter_protocol.dart';
import '../../services/terminal/workspace_terminal_registry.dart';
import '../../services/workspace/workspace_run_registry.dart';
import '../../services/workspace/workspace_tools_scope_registry.dart';
import '../../services/workspace/workspace_pane_policy.dart';
import '../../services/workspace/workspace_worktree_registry.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/workspace/workspace_display_name.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../widgets/run/run_toolbar.dart';
import '../../widgets/ssh/ssh_home_disconnected_banner.dart';
import '../../widgets/termux/termux_disconnected_banner.dart';
import '../floating_workspace/floating_workspace_host.dart';
import '../../repositories/session_repository.dart';
import 'home_new_workspace_dialog.dart';
import 'home_workspace_body_stack.dart';
import 'home_workspace_tab_scope.dart';
import 'home_workspace_title_bar.dart';
import 'global_resource_manager_host.dart';
import 'open_workspace_tab_actions.dart';
import 'workspace_chrome_commands.dart';

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

  /// Location to open when activating [tab]: last deep link for that tab if
  /// known, otherwise the bare workspace path.
  @visibleForTesting
  static String resolveTabRoute({
    required WorkspaceTabRef tab,
    required Map<String, String> restorableLocations,
  }) {
    final restored = restorableLocations[tab.tabKey]?.trim();
    if (restored != null && restored.isNotEmpty) return restored;
    return tab.route;
  }

  /// Tab to activate for `workbench.workspace.nextTab`: the tab after
  /// [activeTabKey] in [tabs], wrapping from the last tab back to the
  /// first. Returns the first tab when [activeTabKey] is `null` or not
  /// found (e.g. currently on the home landing), and `null` when [tabs] is
  /// empty.
  @visibleForTesting
  static WorkspaceTabRef? nextTab({
    required List<WorkspaceTabRef> tabs,
    required String? activeTabKey,
  }) {
    if (tabs.isEmpty) return null;
    final idx = tabs.indexWhere((t) => t.tabKey == activeTabKey);
    if (idx == -1) return tabs.first;
    return tabs[(idx + 1) % tabs.length];
  }

  /// Tab to activate for `workbench.workspace.prevTab`: the tab before
  /// [activeTabKey] in [tabs], wrapping from the first tab back to the
  /// last. Returns the last tab when [activeTabKey] is `null` or not found,
  /// and `null` when [tabs] is empty.
  @visibleForTesting
  static WorkspaceTabRef? prevTab({
    required List<WorkspaceTabRef> tabs,
    required String? activeTabKey,
  }) {
    if (tabs.isEmpty) return null;
    final idx = tabs.indexWhere((t) => t.tabKey == activeTabKey);
    if (idx == -1) return tabs.last;
    return tabs[(idx - 1 + tabs.length) % tabs.length];
  }
}

class _HomeShellState extends State<HomeShell> {
  final _recentWorkspacesStore = HomeRecentWorkspacesStore();
  final _closedWorkspacesStore = HomeClosedWorkspacesStore();
  final _openWorkspacesStore = HomeOpenWorkspacesStore();

  late List<WorkspaceTabRef> _openTabs;
  List<HomeClosedWorkspaceEntry> _recentlyClosed = const [];

  /// Last in-tab location (incl. query) so Home ↔ workspace tab switches restore
  /// manage/section deep links instead of dropping back to the bare workspace path.
  final Map<String, String> _tabRestorableLocations = {};

  late CommandBus _commandBus;
  late WorkspaceChromeCommands _chromeCommands;

  @override
  void initState() {
    super.initState();
    final cache = context.read<HomeWorkspaceUiCache>();
    final routeTab = WorkspaceTabRef.fromLocation(widget.location);
    _openTabs = HomeShell.mergeOpenTabs(
      persisted: cache.openWorkspaceTabs,
      routeTab: routeTab,
    );
    if (routeTab != null) {
      _tabRestorableLocations[routeTab.tabKey] = widget.location;
    }
    _registerChromeCommands();
    unawaited(_finishOpenTabsBootstrap(routeTab));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncFloatingActiveWorkspace();
    });
    if (routeTab == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncTeamSessionScope(context);
      });
    }
  }

  void _registerChromeCommands() {
    _commandBus = context.read<CommandBus>();
    _chromeCommands = context.read<WorkspaceChromeCommands>();
    _commandBus
      ..register(CommandIds.workspaceNextTab, _nextWorkspaceTab)
      ..register(CommandIds.workspacePrevTab, _prevWorkspaceTab)
      ..register(CommandIds.workspaceCloseTab, _closeActiveWorkspaceTab)
      ..register(
        CommandIds.workspaceReopenClosed,
        _reopenClosedWorkspaceTab,
      );
    _chromeCommands
      ..nextWorkspaceTab = _nextWorkspaceTab
      ..prevWorkspaceTab = _prevWorkspaceTab
      ..closeActiveWorkspaceTab = _closeActiveWorkspaceTab
      ..reopenClosedWorkspaceTab = _reopenClosedWorkspaceTab
      ..openTabCount = _openTabs.length;
  }

  void _nextWorkspaceTab() {
    final target = HomeShell.nextTab(
      tabs: _openTabs,
      activeTabKey: WorkspaceTabRef.fromLocation(widget.location)?.tabKey,
    );
    if (target != null) _selectTab(target);
  }

  void _prevWorkspaceTab() {
    final target = HomeShell.prevTab(
      tabs: _openTabs,
      activeTabKey: WorkspaceTabRef.fromLocation(widget.location)?.tabKey,
    );
    if (target != null) _selectTab(target);
  }

  void _closeActiveWorkspaceTab() {
    final activeTab = WorkspaceTabRef.fromLocation(widget.location);
    if (activeTab == null) return;
    unawaited(_closeTab(activeTab.tabKey));
  }

  void _reopenClosedWorkspaceTab() {
    final entry = _recentlyClosed.firstOrNull;
    if (entry == null) return;
    unawaited(_reopenClosedTab(entry.tabKey));
  }

  void _syncFloatingActiveWorkspace() {
    final tab = WorkspaceTabRef.fromLocation(widget.location);
    final floating = context.read<FloatingWorkspaceCubit>();
    if (tab != null) {
      floating.setActiveWorkspace(tab.workspaceId);
    }
    try {
      final insets = context.read<FloatingMaximizeInsets>();
      if (tab == null) {
        // Home / global views: card padding only (covers full card width).
        final isMobile = TpSidebarScope.maybeOf(context)?.isMobile ?? false;
        insets.update(
          FloatingMaximizeInsets.cardSafeArea(isMobile: isMobile),
        );
      }
    } catch (_) {
      // Provider may be absent in isolated widget tests.
    }
  }

  /// Updates [_openTabs] and keeps [_chromeCommands] in sync — every mutation
  /// of the open-tab list must go through this instead of a bare `setState`.
  void _setOpenTabs(List<WorkspaceTabRef> next) {
    setState(() => _openTabs = next);
    _chromeCommands.openTabCount = next.length;
  }

  @override
  void dispose() {
    _commandBus
      ..unregister(CommandIds.workspaceNextTab, _nextWorkspaceTab)
      ..unregister(CommandIds.workspacePrevTab, _prevWorkspaceTab)
      ..unregister(CommandIds.workspaceCloseTab, _closeActiveWorkspaceTab)
      ..unregister(
        CommandIds.workspaceReopenClosed,
        _reopenClosedWorkspaceTab,
      );
    _chromeCommands.clear();
    super.dispose();
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
      _syncFloatingActiveWorkspace();
      final routeTab = WorkspaceTabRef.fromLocation(widget.location);
      if (routeTab != null) {
        _tabRestorableLocations[routeTab.tabKey] = widget.location;
        if (!_openTabs.any((t) => t.tabKey == routeTab.tabKey)) {
          _setOpenTabs([..._openTabs, routeTab]);
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

  void _selectTab(WorkspaceTabRef tab) {
    context.go(
      HomeShell.resolveTabRoute(
        tab: tab,
        restorableLocations: _tabRestorableLocations,
      ),
    );
  }

  void _goHome() => context.go('/home-v2');

  void _openTab(WorkspaceTabRef tab, {required bool activate}) {
    if (!_openTabs.any((t) => t.tabKey == tab.tabKey)) {
      _setOpenTabs([..._openTabs, tab]);
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
    _tabRestorableLocations.remove(tabKey);
    _setOpenTabs(next);
    await _persistOpenTabs();
    await _reloadRecentlyClosed();
    if (!mounted) return;

    terminalRegistry.disposeWorkspace(tab.tabKey);
    context.read<WorkbenchCubit>().clearWorkspace(tab.workspaceId);
    context.read<FloatingWorkspaceCubit>().disposeWorkspace(tab.workspaceId);
    workspaceTools.removeWorkspace(tab.tabKey);
    context.read<WorkspaceToolsScopeRegistry>().removeScope(tab.tabKey);
    context.read<WorkspaceRunRegistry>().removeScope(tab.tabKey);

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
      builder: (dialogContext) => TpDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(
              title: l10n.homeWorkspaceCloseWorkspaceTitle,
              onClose: () => Navigator.of(dialogContext).pop(false),
            ),
            const SizedBox(height: 16),
            Text(l10n.homeWorkspaceCloseWorkspaceMessage(running)),
            TpDialogActions(
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
        child: TpSidebarProvider(
          mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
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
                  onCreateWorkspace: () {
                    unawaited(
                      showHomeNewWorkspaceDialog(
                        context,
                        chatCubit: context.read<ChatCubit>(),
                        repository: context.read<SessionRepository>(),
                      ),
                    );
                  },
                ),
                const TermuxDisconnectedBanner(),
                const SshHomeDisconnectedBanner(),
              Expanded(
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: FloatingWorkspaceHost(
                    child: HomeTabScope(
                      openWorkspace: (id, {activate = true}) =>
                          _openWorkspace(id, activate: activate),
                      child: GlobalResourceManagerHost(
                        child: HomeWorkspaceBodyStack(
                          location: widget.location,
                          openTabs: _openTabs,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
    required this.onCreateWorkspace,
  });

  final String location;
  final List<WorkspaceTabRef> openTabs;
  final List<HomeClosedWorkspaceEntry> recentlyClosed;
  final VoidCallback onHomeTap;
  final ValueChanged<String> onSelectTab;
  final ValueChanged<String> onCloseTab;
  final ValueChanged<String> onReopenClosedTab;
  final VoidCallback onCreateWorkspace;

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
      trailingActions: _runToolbarForActiveTab(
        context: context,
        activeTab: activeTab,
        openWorkspaces: openWorkspaces,
      ),
      onHomeTap: onHomeTap,
      onSelectTab: onSelectTab,
      onCloseTab: onCloseTab,
      onReopenClosedTab: onReopenClosedTab,
      onCreateWorkspace: onCreateWorkspace,
    );
  }

  Widget? _runToolbarForActiveTab({
    required BuildContext context,
    required WorkspaceTabRef? activeTab,
    required List<Workspace> openWorkspaces,
  }) {
    if (activeTab == null) return null;
    final workspace = _HomeShellState._resolve(
      openWorkspaces,
      activeTab.workspaceId,
    );
    if (workspace == null) return null;
    final runCubit = context.read<WorkspaceRunRegistry>().cubitFor(
      tabScopeId: activeTab.tabKey,
      workspaceId: workspace.workspaceId,
      folders: workspace.folders,
    );
    return BlocProvider<RunCubit>.value(
      value: runCubit,
      child: RunToolbar(
        workspaceId: workspace.workspaceId,
        showFolderLabels: workspace.folders.length > 1,
        pickActionResult: _pickRunActionResult,
      ),
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

Future<Map<String, Object?>?> _pickRunActionResult(
  LaunchAdapterConfigurationEntry action,
) async {
  final result = await FilePicker.platform.pickFiles(type: FileType.any);
  final files = result?.files;
  if (files == null || files.isEmpty) return null;
  final path = files.first.path;
  if (path == null || path.isEmpty) return null;
  return {'path': path, 'name': p.basename(path)};
}
