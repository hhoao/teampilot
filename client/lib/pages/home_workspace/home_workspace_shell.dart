import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../cubits/workspace_tools_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_project.dart';
import '../../utils/project_display_name.dart';
import '../../models/team_config.dart';
import '../../models/home_closed_project_entry.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../services/home_workspace/home_workspace_closed_projects_store.dart';
import '../../services/home_workspace/home_workspace_open_projects_store.dart';
import '../../services/home_workspace/home_workspace_recent_projects_store.dart';
import '../../services/terminal/workspace_terminal_registry.dart';
import '../../widgets/app_dialog.dart';
import 'home_workspace_tab_scope.dart';
import 'home_workspace_title_bar.dart';

/// Persistent chrome for the workspace-home route family. Owns the open project
/// tabs (kept until explicitly closed) and renders the title bar once above the
/// routed [child] (home view or a project view).
class HomeWorkspaceShell extends StatefulWidget {
  const HomeWorkspaceShell({
    required this.location,
    required this.child,
    super.key,
  });

  /// Current router location (e.g. `/home-v2` or `/home-v2/project/<id>`).
  final String location;
  final Widget child;

  @override
  State<HomeWorkspaceShell> createState() => _HomeWorkspaceShellState();

  @visibleForTesting
  static String formatProjectTabTooltip({
    required AppProject project,
    required String personalKindLabel,
    String? teamName,
    String? displayName,
  }) {
    final name = displayName ?? project.effectiveDisplay;
    final prefix = project.teamId.isEmpty
        ? personalKindLabel
        : ((teamName != null && teamName.isNotEmpty)
              ? teamName
              : project.teamId);
    final headline = '$prefix · $name';
    final path = project.primaryPath.trim();
    if (path.isEmpty || path == name) return headline;
    return '$headline\n$path';
  }

  static String? teamNameFor(List<TeamConfig> teams, String teamId) {
    if (teamId.isEmpty) return null;
    for (final team in teams) {
      if (team.id == teamId) return team.name;
    }
    return null;
  }
}

class _HomeWorkspaceShellState extends State<HomeWorkspaceShell> {
  final _recentProjectsStore = HomeWorkspaceRecentProjectsStore();
  final _closedProjectsStore = HomeWorkspaceClosedProjectsStore();
  final _openProjectsStore = HomeWorkspaceOpenProjectsStore();

  /// Open project ids in tab order; persisted across app restarts. The built-in
  /// personal project is always pinned first and cannot be closed.
  List<String> _openIds = const [AppProject.defaultPersonalId];
  List<HomeClosedProjectEntry> _recentlyClosed = const [];

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
    final initialProjectId = _projectIdFromLocation(widget.location);
    final persisted = await _openProjectsStore.loadOrderedIds();
    if (!mounted) return;
    setState(
      () => _openIds = _mergeOpenIds(
        persisted: persisted,
        routeProjectId: initialProjectId,
      ),
    );
    if (initialProjectId != null) {
      unawaited(_recentProjectsStore.recordVisit(initialProjectId));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<LayoutCubit>().setLastOpenedProjectId(initialProjectId);
      });
    }
    await _persistOpenIds();
    await _reloadRecentlyClosed();
  }

  static List<String> _mergeOpenIds({
    required List<String> persisted,
    required String? routeProjectId,
  }) {
    final merged = <String>[AppProject.defaultPersonalId];
    void add(String raw) {
      final id = raw.trim();
      if (id.isEmpty || merged.contains(id)) return;
      merged.add(id);
    }

    for (final id in persisted) {
      if (id != AppProject.defaultPersonalId) add(id);
    }
    if (routeProjectId != null) add(routeProjectId);
    return merged;
  }

  Future<void> _persistOpenIds() async {
    await _openProjectsStore.saveOrderedIds(_openIds);
  }

  Future<void> _reloadRecentlyClosed() async {
    final all = await _closedProjectsStore.load();
    if (!mounted) return;
    final open = _openIds.toSet();
    setState(
      () => _recentlyClosed = [
        for (final e in all)
          if (!open.contains(e.projectId)) e,
      ],
    );
  }

  @override
  void didUpdateWidget(covariant HomeWorkspaceShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      final id = _projectIdFromLocation(widget.location);
      if (id != null) {
        if (!_openIds.contains(id)) {
          setState(() => _openIds = [..._openIds, id]);
          unawaited(_persistOpenIds());
        }
        unawaited(_recentProjectsStore.recordVisit(id));
        context.read<LayoutCubit>().setLastOpenedProjectId(id);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncTeamSessionScope(context);
      });
    }
  }

  static String? _projectIdFromLocation(String location) {
    final segments = Uri.parse(location).pathSegments;
    if (segments.length >= 3 &&
        segments[0] == 'home-v2' &&
        segments[1] == 'project') {
      return segments[2];
    }
    return null;
  }

  void _selectTab(String id) {
    context.go('/home-v2/project/$id');
  }

  void _goHome() => context.go('/home-v2');

  void _openProject(String id, {required bool activate}) {
    if (!_openIds.contains(id)) {
      setState(() => _openIds = [..._openIds, id]);
      unawaited(_persistOpenIds());
    }
    unawaited(_recentProjectsStore.recordVisit(id));
    if (activate) {
      _selectTab(id);
    }
  }

  Future<void> _reopenClosedProject(String id) async {
    await _closedProjectsStore.remove(id);
    if (!mounted) return;
    _openProject(id, activate: true);
    await _reloadRecentlyClosed();
  }

  Future<void> _closeTab(String id) async {
    // The pinned personal project is permanent — never closes.
    if (id == AppProject.defaultPersonalId) return;
    if (!_openIds.contains(id)) return;
    final projects = context.read<ChatCubit>().state.projects;
    final project = _resolve(projects, id);
    // Closing a project tab always terminates that project's running sessions;
    // confirm first when there are any so the user can cancel.
    final chat = context.read<ChatCubit>();
    final terminalRegistry = context.read<WorkspaceTerminalRegistry>();
    final workspaceTools = context.read<WorkspaceToolsCubit>();
    final running = chat.openTabCountForProject(id);
    if (running > 0) {
      final confirmed = await _confirmCloseWithSessions(running);
      if (confirmed != true || !mounted) return;
      chat.closeTabsForProject(id);
    }
    final idx = _openIds.indexOf(id);
    if (idx < 0) return;
    // Persist closed/open tab state before teardown so a crash or fast quit
    // cannot drop the recently-closed entry.
    await _closedProjectsStore.recordClosed(
      HomeClosedProjectEntry(
        projectId: id,
        displayName: project?.effectiveDisplay ?? id,
        primaryPath: project?.primaryPath ?? '',
      ),
    );
    if (!mounted) return;
    final wasActive = id == _projectIdFromLocation(widget.location);
    final next = [..._openIds]..removeAt(idx);
    setState(() => _openIds = next);
    await _persistOpenIds();
    await _reloadRecentlyClosed();
    if (!mounted) return;
    // Tear down this project's keep-alive workspace runtime.
    terminalRegistry.disposeProject(id);
    workspaceTools.removeProject(id);
    if (running == 0) {
      // No chat sessions to confirm/close, but still drop any chat bucket.
      chat.closeTabsForProject(id);
    }
    if (wasActive) {
      // Fall back to the nearest still-resolvable tab. The pinned personal id
      // can be a phantom (SSH/Android, where it is not seeded), so skip ids that
      // resolve to no project and land on Home instead of an empty page.
      final candidates = [
        for (final e in next)
          if (_resolve(projects, e) != null) e,
      ];
      if (candidates.isEmpty) {
        _goHome();
      } else {
        final target = idx.clamp(0, candidates.length - 1);
        _selectTab(candidates[target]);
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
              title: l10n.homeWorkspaceCloseProjectTitle,
              onClose: () => Navigator.of(dialogContext).pop(false),
            ),
            const SizedBox(height: 16),
            Text(l10n.homeWorkspaceCloseProjectMessage(running)),
            AppDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(l10n.homeWorkspaceCloseProjectConfirm),
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
    final selectedTeam = context.read<TeamCubit>().state.selectedTeam;
    final projects = context.read<ChatCubit>().state.projects;
    final activeId = _projectIdFromLocation(widget.location);
    final activeProject =
        activeId != null ? _resolve(projects, activeId) : null;
    final scopeTeamId = activeProject != null
        ? (activeProject.teamId.isNotEmpty ? activeProject.teamId : '')
        : selectedTeam?.id;
    context.read<ChatCubit>().setTeamSessionScope(
      scopeSessionsToSelectedTeam: scopeOn,
      selectedTeamId: scopeTeamId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final projects = context.select<ChatCubit, List<AppProject>>(
      (c) => c.state.projects,
    );
    final activeId = _projectIdFromLocation(widget.location);
    final pageChrome = activeId == null
        ? WorkspacePageChrome.home
        : WorkspacePageChrome.project;

    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final teams = context.select<TeamCubit, List<TeamConfig>>(
      (c) => c.state.teams,
    );
    // Show every open project tab across all teams (IDE-style open editors).
    // Selecting a tab switches the active team to the project's team via
    // HomeWorkspaceProjectPage, so the sidebar/content stay in sync.
    final tabs = <HomeProjectTab>[
      for (final id in _openIds)
        if (_resolve(projects, id) case final p?)
          HomeProjectTab(
            id: id,
            name: p.localizedName(l10n),
            kind: p.teamId.isEmpty
                ? HomeProjectTabKind.personal
                : HomeProjectTabKind.team,
            tooltip: HomeWorkspaceShell.formatProjectTabTooltip(
              project: p,
              personalKindLabel: l10n.homeWorkspaceProjectTabKindPersonal,
              teamName: HomeWorkspaceShell.teamNameFor(teams, p.teamId),
              displayName: p.localizedName(l10n),
            ),
            closable: !p.isDefaultPersonal,
          ),
    ];

    return BlocListener<SessionPreferencesCubit, SessionPreferencesState>(
      listenWhen: (previous, next) =>
          previous.preferences.scopeSessionsToSelectedTeam !=
          next.preferences.scopeSessionsToSelectedTeam,
      listener: (context, _) => _syncTeamSessionScope(context),
      child: BlocListener<TeamCubit, TeamState>(
        listenWhen: (previous, next) =>
            previous.selectedTeam?.id != next.selectedTeam?.id,
        listener: (context, _) => _syncTeamSessionScope(context),
        child: Scaffold(
          backgroundColor: cs.workspacePageChrome(pageChrome),
          body: Column(
            children: [
              HomeWorkspaceTitleBar(
            tabs: tabs,
            activeProjectId: activeId,
            pageChrome: pageChrome,
            recentlyClosed: _recentlyClosed,
            openProjectIds: _openIds.toSet(),
            onHomeTap: _goHome,
            onSelectTab: _selectTab,
            onCloseTab: _closeTab,
            onReopenClosedProject: (id) => unawaited(_reopenClosedProject(id)),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: HomeWorkspaceTabScope(
                openProject: (id, {activate = true}) =>
                    _openProject(id, activate: activate),
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

  static AppProject? _resolve(List<AppProject> projects, String id) {
    for (final p in projects) {
      if (p.projectId == id) return p;
    }
    return null;
  }

}
