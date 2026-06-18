import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/identity_cubit.dart';
import '../../cubits/workspace_tools_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_workspace.dart';
import '../../models/launch_identity.dart';
import '../../models/identity_kind.dart';
import '../../models/team_config.dart';
import '../../models/identity.dart';
import '../../services/storage/identity_provisioner.dart';
import '../../utils/workspace_display_name.dart';
import '../../models/home_closed_workspace_entry.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../services/home_workspace/home_workspace_closed_workspaces_store.dart';
import '../../services/home_workspace/home_workspace_open_workspaces_store.dart';
import '../../services/home_workspace/home_workspace_recent_workspaces_store.dart';
import '../../services/terminal/workspace_terminal_registry.dart';
import '../../widgets/app_dialog.dart';
import 'home_workspace_tab_scope.dart';
import 'home_workspace_title_bar.dart';

/// Persistent chrome for the workspace-home route family. Owns the open workspace
/// tabs (kept until explicitly closed) and renders the title bar once above the
/// routed [child] (home view or a workspace view).
class HomeShell extends StatefulWidget {
  const HomeShell({
    required this.location,
    required this.child,
    super.key,
  });

  /// Current router location (path + query), e.g. `/home-v2/workspace/<id>?as=personal`.
  final String location;
  final Widget child;

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
    final path = workspace.primaryPath.trim();
    if (path.isEmpty || path == name) return headline;
    return '$headline\n$path';
  }

  static String? identityNameFor(
    List<Identity> identities,
    String identityId,
  ) {
    if (identityId.isEmpty) return null;
    for (final identity in identities) {
      if (identity.id == identityId) {
        return identity is TeamIdentity
            ? identity.name
            : identity.display;
      }
    }
    return null;
  }

  @Deprecated('Use identityNameFor')
  static String? teamNameFor(List<TeamIdentity> teams, String teamId) =>
      identityNameFor(teams, teamId);
}

class _HomeShellState extends State<HomeShell> {
  final _recentWorkspacesStore = HomeRecentWorkspacesStore();
  final _closedWorkspacesStore = HomeClosedWorkspacesStore();
  final _openWorkspacesStore = HomeOpenWorkspacesStore();

  /// Open workspace ids in tab order; persisted across app restarts.
  List<String> _openIds = const [];
  List<HomeClosedWorkspaceEntry> _recentlyClosed = const [];
  final Map<String, LaunchIdentity> _identityByWorkspaceId = {};

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
    final initialWorkspaceId = _workspaceIdFromLocation(widget.location);
    final initialIdentity = _identityFromLocation(widget.location);
    if (initialWorkspaceId != null && initialIdentity != null) {
      _identityByWorkspaceId[initialWorkspaceId] = initialIdentity;
    }
    final persisted = await _openWorkspacesStore.loadOrderedIds();
    if (!mounted) return;
    setState(
      () => _openIds = _mergeOpenIds(
        persisted: persisted,
        routeWorkspaceId: initialWorkspaceId,
      ),
    );
    if (initialWorkspaceId != null) {
      unawaited(_recentWorkspacesStore.recordVisit(initialWorkspaceId));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<LayoutCubit>().setLastOpenedWorkspaceId(initialWorkspaceId);
      });
    }
    await _persistOpenIds();
    await _reloadRecentlyClosed();
  }

  static List<String> _mergeOpenIds({
    required List<String> persisted,
    required String? routeWorkspaceId,
  }) {
    final merged = <String>[];
    void add(String raw) {
      final id = raw.trim();
      if (id.isEmpty || merged.contains(id)) return;
      merged.add(id);
    }

    for (final id in persisted) {
      add(id);
    }
    if (routeWorkspaceId != null) add(routeWorkspaceId);
    return merged;
  }

  Future<void> _persistOpenIds() async {
    await _openWorkspacesStore.saveOrderedIds(_openIds);
  }

  Future<void> _reloadRecentlyClosed() async {
    final all = await _closedWorkspacesStore.load();
    if (!mounted) return;
    final open = _openIds.toSet();
    setState(
      () => _recentlyClosed = [
        for (final e in all)
          if (!open.contains(e.workspaceId)) e,
      ],
    );
  }

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      final id = _workspaceIdFromLocation(widget.location);
      final identity = _identityFromLocation(widget.location);
      if (id != null) {
        if (identity != null) {
          _identityByWorkspaceId[id] = identity;
        }
        if (!_openIds.contains(id)) {
          setState(() => _openIds = [..._openIds, id]);
          unawaited(_persistOpenIds());
        }
        unawaited(_recentWorkspacesStore.recordVisit(id));
        context.read<LayoutCubit>().setLastOpenedWorkspaceId(id);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncTeamSessionScope(context);
      });
    }
  }

  static String? _workspaceIdFromLocation(String location) {
    final uri = _parseLocationUri(location);
    final segments = uri.pathSegments;
    if (segments.length >= 3 &&
        segments[0] == 'home-v2' &&
        segments[1] == 'workspace') {
      return segments[2];
    }
    return null;
  }

  static LaunchIdentity? _identityFromLocation(String location) =>
      LaunchIdentity.decode(_parseLocationUri(location).queryParameters['as']);

  static Uri _parseLocationUri(String location) {
    if (location.startsWith('http://') || location.startsWith('https://')) {
      return Uri.parse(location);
    }
    return Uri.parse('http://local$location');
  }

  LaunchIdentity _identityForWorkspace(String workspaceId) {
    final fromRoute = _workspaceIdFromLocation(widget.location) == workspaceId
        ? _identityFromLocation(widget.location)
        : null;
    return fromRoute ??
        _identityByWorkspaceId[workspaceId] ??
        const LaunchIdentity(IdentityProvisioner.defaultPersonalId);
  }

  String _workspaceRoute(String workspaceId, LaunchIdentity identity) =>
      '/home-v2/workspace/$workspaceId?as=${identity.encode()}';

  void _selectTab(String id) {
    context.go(_workspaceRoute(id, _identityForWorkspace(id)));
  }

  void _goHome() => context.go('/home-v2');

  void _openWorkspace(String id, {required bool activate}) {
    if (!_openIds.contains(id)) {
      setState(() => _openIds = [..._openIds, id]);
      unawaited(_persistOpenIds());
    }
    unawaited(_recentWorkspacesStore.recordVisit(id));
    if (activate) {
      _selectTab(id);
    }
  }

  Future<void> _reopenClosedWorkspace(String id) async {
    await _closedWorkspacesStore.remove(id);
    if (!mounted) return;
    _openWorkspace(id, activate: true);
    await _reloadRecentlyClosed();
  }

  Future<void> _closeTab(String id) async {
    if (!_openIds.contains(id)) return;
    final workspaces = context.read<ChatCubit>().state.workspaces;
    final workspace = _resolve(workspaces, id);
    // Closing a workspace tab always terminates that workspace's running sessions;
    // confirm first when there are any so the user can cancel.
    final chat = context.read<ChatCubit>();
    final terminalRegistry = context.read<WorkspaceTerminalRegistry>();
    final workspaceTools = context.read<WorkspaceToolsCubit>();
    final running = chat.openTabCountForWorkspace(id);
    if (running > 0) {
      final confirmed = await _confirmCloseWithSessions(running);
      if (confirmed != true || !mounted) return;
      chat.closeTabsForWorkspace(id);
    }
    final idx = _openIds.indexOf(id);
    if (idx < 0) return;
    // Persist closed/open tab state before teardown so a crash or fast quit
    // cannot drop the recently-closed entry.
    await _closedWorkspacesStore.recordClosed(
      HomeClosedWorkspaceEntry(
        workspaceId: id,
        displayName: workspace?.effectiveDisplay ?? id,
        primaryPath: workspace?.primaryPath ?? '',
      ),
    );
    if (!mounted) return;
    final wasActive = id == _workspaceIdFromLocation(widget.location);
    final next = [..._openIds]..removeAt(idx);
    setState(() => _openIds = next);
    await _persistOpenIds();
    await _reloadRecentlyClosed();
    if (!mounted) return;
    // Tear down this workspace's keep-alive workspace runtime.
    terminalRegistry.disposeWorkspace(id);
    workspaceTools.removeWorkspace(id);
    if (running == 0) {
      // No chat sessions to confirm/close, but still drop any chat bucket.
      chat.closeTabsForWorkspace(id);
    }
    if (wasActive) {
      final candidates = [
        for (final e in next)
          if (_resolve(workspaces, e) != null) e,
      ];
      if (candidates.isEmpty) {
        _goHome();
      } else {
        final target = idx.clamp(0, candidates.length - 1);
        _selectTab(candidates[target]);
      }
    }
    _identityByWorkspaceId.remove(id);
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
    final selectedTeam = context.read<IdentityCubit>().state.selectedTeam;
    final activeId = _workspaceIdFromLocation(widget.location);
    final activeIdentity =
        activeId != null ? _identityForWorkspace(activeId) : null;
    final scopeTeamId = activeIdentity != null
        ? _sessionTeamScopeId(context, activeIdentity)
        : selectedTeam?.id;
    context.read<ChatCubit>().setTeamSessionScope(
      scopeSessionsToSelectedTeam: scopeOn,
      selectedTeamId: scopeTeamId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspaces = context.select<ChatCubit, List<Workspace>>(
      (c) => c.state.workspaces,
    );
    final activeId = _workspaceIdFromLocation(widget.location);
    final pageChrome = activeId == null
        ? WorkspacePageChrome.home
        : WorkspacePageChrome.workspace;

    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final identities = context.select<IdentityCubit, List<Identity>>(
      (c) => c.state.identities,
    );
    // Show every open workspace tab across all teams (IDE-style open editors).
    // Selecting a tab switches the active team to the workspace's team via
    // WorkspacePage, so the sidebar/content stay in sync.
    final tabs = <HomeWorkspaceTab>[
      for (final id in _openIds)
        if (_resolve(workspaces, id) case final p?)
          _workspaceTab(
            id: id,
            workspace: p,
            l10n: l10n,
            identities: identities,
          ),
    ];

    return BlocListener<SessionPreferencesCubit, SessionPreferencesState>(
      listenWhen: (previous, next) =>
          previous.preferences.scopeSessionsToSelectedTeam !=
          next.preferences.scopeSessionsToSelectedTeam,
      listener: (context, _) => _syncTeamSessionScope(context),
      child: BlocListener<IdentityCubit, IdentityState>(
        listenWhen: (previous, next) =>
            previous.selectedTeam?.id != next.selectedTeam?.id,
        listener: (context, _) => _syncTeamSessionScope(context),
        child: Scaffold(
          backgroundColor: cs.workspacePageChrome(pageChrome),
          body: Column(
            children: [
              HomeTitleBar(
            tabs: tabs,
            activeWorkspaceId: activeId,
            pageChrome: pageChrome,
            recentlyClosed: _recentlyClosed,
            openWorkspaceIds: _openIds.toSet(),
            onHomeTap: _goHome,
            onSelectTab: _selectTab,
            onCloseTab: _closeTab,
            onReopenClosedWorkspace: (id) => unawaited(_reopenClosedWorkspace(id)),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: HomeTabScope(
                openWorkspace: (id, {activate = true}) =>
                    _openWorkspace(id, activate: activate),
                child: widget.child,
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
    required String id,
    required Workspace workspace,
    required AppLocalizations l10n,
    required List<Identity> identities,
  }) {
    final identity = _identityForWorkspace(id);
    final workspaceIdentity = identities
            .where((e) => e.id == identity.identityId)
            .firstOrNull ??
        identities
            .where((e) => e.id == IdentityProvisioner.defaultPersonalId)
            .firstOrNull;
    final isPersonal = workspaceIdentity?.kind == IdentityKind.personal;
    final identityId = identity.identityId;
    return HomeWorkspaceTab(
      id: id,
      name: workspace.localizedName(l10n),
      kind: isPersonal ? HomeWorkspaceTabKind.personal : HomeWorkspaceTabKind.team,
      tooltip: HomeShell.formatWorkspaceTabTooltip(
        workspace: workspace,
        personalKindLabel: l10n.homeWorkspaceWorkspaceTabKindPersonal,
        isPersonal: isPersonal,
        teamName: HomeShell.identityNameFor(identities, identityId),
        teamId: identityId,
        displayName: workspace.localizedName(l10n),
      ),
      closable: true,
    );
  }

  static String _sessionTeamScopeId(
    BuildContext context,
    LaunchIdentity identity,
  ) {
    final workspaceIdentity = context.read<IdentityCubit>().byId(
          identity.identityId,
        );
    if (workspaceIdentity?.kind == IdentityKind.personal) return '';
    return identity.identityId;
  }

  static Workspace? _resolve(List<Workspace> workspaces, String id) {
    for (final p in workspaces) {
      if (p.workspaceId == id) return p;
    }
    return null;
  }

}
