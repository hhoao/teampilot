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
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../models/launch_profile_ref.dart';
import '../../models/launch_profile_kind.dart';
import '../../models/launch_profile.dart';
import '../../models/workspace_tab_ref.dart';
import '../../services/storage/launch_profile_provisioner.dart';
import '../../utils/launch_profile_display_name.dart';
import '../../utils/workspace_display_name.dart';
import '../../models/home_closed_workspace_entry.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../services/home_workspace/home_closed_workspaces_store.dart';
import '../../services/home_workspace/home_open_workspaces_store.dart';
import '../../services/home_workspace/home_recent_workspaces_store.dart';
import '../../services/file_tree/workspace_file_tree_store.dart';
import '../../services/terminal/workspace_terminal_registry.dart';
import '../../widgets/app_dialog.dart';
import 'home_workspace_body_stack.dart';
import 'home_workspace_tab_scope.dart';
import 'home_workspace_title_bar.dart';
import 'open_workspace_tab_actions.dart';

/// Persistent chrome for the workspace-home route family. Owns the open workspace
/// tabs (kept until explicitly closed), the title bar, and [HomeWorkspaceBodyStack]
/// (GoRouter supplies the URL only — not the body widget tree).
class HomeShell extends StatefulWidget {
  const HomeShell({
    required this.location,
    super.key,
  });

  /// Current router location (path + query), e.g. `/home-v2/workspace/<id>?as=personal`.
  final String location;

  @override
  State<HomeShell> createState() => _HomeShellState();

  @visibleForTesting
  static String formatWorkspaceTabTooltip({
    required Workspace workspace,
    required String personalKindLabel,
    required bool isPersonal,
    String? teamName,
    String? teamId,
    String? displayName,
  }) {
    final name = displayName ?? workspace.effectiveDisplay;
    final prefix = isPersonal
        ? personalKindLabel
        : ((teamName != null && teamName.isNotEmpty)
              ? teamName
              : teamId ?? '');
    final headline = '$prefix · $name';
    final path = workspace.firstFolderPath.trim();
    if (path.isEmpty || path == name) return headline;
    return '$headline\n$path';
  }

  static String? identityNameFor(
    AppLocalizations l10n,
    List<LaunchProfile> identities,
    String profileId,
  ) =>
      launchProfileDisplayNameForId(l10n, identities, profileId);

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

  /// Open workspace tabs in display order; persisted across app restarts.
  List<WorkspaceTabRef> _openTabs = const [];
  List<HomeClosedWorkspaceEntry> _recentlyClosed = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrapOpenTabs());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncTeamSessionScope(context);
    });
  }

  Future<void> _bootstrapOpenTabs() async {
    final routeTab = WorkspaceTabRef.fromLocation(widget.location);
    final persisted = await _openWorkspacesStore.loadOrderedTabs();
    if (!mounted) return;
    setState(
      () => _openTabs = HomeShell.mergeOpenTabs(
        persisted: persisted,
        routeTab: routeTab,
      ),
    );
    if (routeTab != null) {
      unawaited(_recentWorkspacesStore.recordVisit(routeTab));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context
            .read<LayoutCubit>()
            .setLastOpenedWorkspaceId(routeTab.workspaceId);
      });
    }
    await _persistOpenTabs();
    await _reloadRecentlyClosed();
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
        context
            .read<LayoutCubit>()
            .setLastOpenedWorkspaceId(routeTab.workspaceId);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncTeamSessionScope(context);
      });
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
    if (activate) {
      _selectTab(tab);
    }
  }

  void _openWorkspace(
    String workspaceId, {
    required bool activate,
    LaunchProfileRef? identity,
  }) {
    final resolved = identity ?? _defaultIdentityFor(workspaceId);
    _openTab(
      WorkspaceTabRef(workspaceId: workspaceId, identity: resolved),
      activate: activate,
    );
  }

  LaunchProfileRef _defaultIdentityFor(String workspaceId) {
    final workspace = _resolve(
      context.read<ChatCubit>().state.workspaces,
      workspaceId,
    );
    final profileId = workspace?.defaultProfileId.trim() ?? '';
    if (profileId.isNotEmpty) {
      return LaunchProfileRef(profileId);
    }
    return const LaunchProfileRef(LaunchProfileProvisioner.defaultPersonalId);
  }

  Future<void> _openTabWithOtherIdentity(String tabKey) async {
    final tab = _openTabs.where((t) => t.tabKey == tabKey).firstOrNull;
    if (tab == null) return;
    final chat = context.read<ChatCubit>();
    final workspace = _resolve(chat.state.workspaces, tab.workspaceId);
    if (workspace == null) return;
    await openWorkspaceInNewTabWithIdentityPicker(
      context,
      workspace: workspace,
      sessions: chat.state.sessions,
      excludeIdentity: tab.identity,
    );
  }

  Future<void> _reopenClosedTab(String tabKey) async {
    final entry = _recentlyClosed
        .where((e) => e.tabKey == tabKey)
        .firstOrNull;
    if (entry == null) return;
    await _closedWorkspacesStore.remove(tabKey);
    if (!mounted) return;
    _openTab(
      WorkspaceTabRef(
        workspaceId: entry.workspaceId,
        identity: entry.identity,
      ),
      activate: true,
    );
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

    final stillOpenSameDirectory = next.any(
      (t) => t.workspaceId == tab.workspaceId,
    );
    if (!stillOpenSameDirectory) {
      context.read<WorkspaceFileTreeStore>().removeWorkspace(tab.workspaceId);
    }
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
    final activeTab = WorkspaceTabRef.fromLocation(widget.location);
    final scopeTeamId = activeTab != null
        ? _sessionTeamScopeId(context, activeTab.identity)
        : selectedTeam?.id;
    context.read<ChatCubit>().setTeamSessionScope(
      scopeSessionsToSelectedTeam: scopeOn,
      selectedTeamId: scopeTeamId,
    );
  }

  bool _hasDuplicateDirectory(WorkspaceTabRef tab) =>
      _openTabs.where((t) => t.workspaceId == tab.workspaceId).length > 1;

  @override
  Widget build(BuildContext context) {
    final workspaces = context.select<ChatCubit, List<Workspace>>(
      (c) => c.state.workspaces,
    );
    final activeTab = WorkspaceTabRef.fromLocation(widget.location);
    final pageChrome = activeTab == null
        ? WorkspacePageChrome.home
        : WorkspacePageChrome.workspace;

    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final identities = context.select<LaunchProfileCubit, List<LaunchProfile>>(
      (c) => c.state.identities,
    );
    final tabs = <HomeWorkspaceTab>[
      for (final tab in _openTabs)
        if (_resolve(workspaces, tab.workspaceId) case final workspace?)
          _workspaceTab(
            tab: tab,
            workspace: workspace,
            l10n: l10n,
            identities: identities,
          ),
    ];

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
          backgroundColor: cs.workspacePageChrome(pageChrome),
          body: Column(
            children: [
              HomeTitleBar(
                tabs: tabs,
                activeTabKey: activeTab?.tabKey,
                pageChrome: pageChrome,
                recentlyClosed: _recentlyClosed,
                onHomeTap: _goHome,
                onSelectTab: (tabKey) {
                  final tab =
                      _openTabs.where((t) => t.tabKey == tabKey).firstOrNull;
                  if (tab != null) _selectTab(tab);
                },
                onCloseTab: (tabKey) => unawaited(_closeTab(tabKey)),
                onReopenClosedTab: (tabKey) => unawaited(_reopenClosedTab(tabKey)),
                onOpenTabWithOtherIdentity: (tabKey) =>
                    unawaited(_openTabWithOtherIdentity(tabKey)),
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: HomeTabScope(
                    openWorkspace: (id, {activate = true, identity}) =>
                        _openWorkspace(
                          id,
                          activate: activate,
                          identity: identity,
                        ),
                    child: HomeWorkspaceBodyStack(
                      location: widget.location,
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

  HomeWorkspaceTab _workspaceTab({
    required WorkspaceTabRef tab,
    required Workspace workspace,
    required AppLocalizations l10n,
    required List<LaunchProfile> identities,
  }) {
    final workspaceIdentity = identities
            .where((e) => e.id == tab.identity.profileId)
            .firstOrNull ??
        identities
            .where((e) => e.id == LaunchProfileProvisioner.defaultPersonalId)
            .firstOrNull;
    final isPersonal = workspaceIdentity?.kind == LaunchProfileKind.personal;
    final profileId = tab.identity.profileId;
    final identityLabel = isPersonal
        ? l10n.homeWorkspaceWorkspaceTabKindPersonal
        : (HomeShell.identityNameFor(l10n, identities, profileId) ?? profileId);
    final workspaceName = workspace.localizedName(l10n);
    final showIdentityInLabel = _hasDuplicateDirectory(tab);
    return HomeWorkspaceTab(
      id: tab.tabKey,
      name: showIdentityInLabel
          ? '$identityLabel · $workspaceName'
          : workspaceName,
      kind: isPersonal ? HomeWorkspaceTabKind.personal : HomeWorkspaceTabKind.team,
      tooltip: HomeShell.formatWorkspaceTabTooltip(
        workspace: workspace,
        personalKindLabel: l10n.homeWorkspaceWorkspaceTabKindPersonal,
        isPersonal: isPersonal,
        teamName: HomeShell.identityNameFor(l10n, identities, profileId),
        teamId: profileId,
        displayName: workspaceName,
      ),
      closable: true,
    );
  }

  static String _sessionTeamScopeId(
    BuildContext context,
    LaunchProfileRef identity,
  ) {
    final workspaceIdentity = context.read<LaunchProfileCubit>().byId(
          identity.profileId,
        );
    if (workspaceIdentity?.kind == LaunchProfileKind.personal) return '';
    return identity.profileId;
  }

  static Workspace? _resolve(List<Workspace> workspaces, String id) {
    for (final p in workspaces) {
      if (p.workspaceId == id) return p;
    }
    return null;
  }
}
