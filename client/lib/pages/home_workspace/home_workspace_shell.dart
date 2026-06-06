import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_project.dart';
import '../../models/home_closed_project_entry.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../services/home_workspace/home_workspace_closed_projects_store.dart';
import '../../services/home_workspace/home_workspace_recent_projects_store.dart';
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
}

class _HomeWorkspaceShellState extends State<HomeWorkspaceShell> {
  final _recentProjectsStore = HomeWorkspaceRecentProjectsStore();
  final _closedProjectsStore = HomeWorkspaceClosedProjectsStore();

  /// Open project ids in tab order; persists across navigation.
  List<String> _openIds = const [];
  List<HomeClosedProjectEntry> _recentlyClosed = const [];

  @override
  void initState() {
    super.initState();
    final initialProjectId = _projectIdFromLocation(widget.location);
    _ensureOpen(initialProjectId);
    if (initialProjectId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<LayoutCubit>().setLastOpenedProjectId(initialProjectId);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncTeamSessionScope(context);
    });
    unawaited(_reloadRecentlyClosed());
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

  void _ensureOpen(String? id) {
    if (id == null) return;
    if (!_openIds.contains(id)) {
      _openIds = [..._openIds, id];
    }
    unawaited(_recentProjectsStore.recordVisit(id));
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
    if (!_openIds.contains(id)) return;
    final projects = context.read<ChatCubit>().state.projects;
    // Closing a project tab always terminates that project's running sessions;
    // confirm first when there are any so the user can cancel.
    final chat = context.read<ChatCubit>();
    final running = chat.openTabCountForProject(id);
    if (running > 0) {
      final confirmed = await _confirmCloseWithSessions(running);
      if (confirmed != true || !mounted) return;
      chat.closeTabsForProject(id);
    }
    final idx = _openIds.indexOf(id);
    if (idx < 0) return;
    final project = _resolve(projects, id);
    if (project != null) {
      await _closedProjectsStore.recordClosed(
        HomeClosedProjectEntry(
          projectId: project.projectId,
          displayName: project.effectiveDisplay,
          primaryPath: project.primaryPath,
        ),
      );
    }
    final wasActive = id == _projectIdFromLocation(widget.location);
    final next = [..._openIds]..removeAt(idx);
    setState(() => _openIds = next);
    await _reloadRecentlyClosed();
    if (wasActive) {
      if (next.isEmpty) {
        _goHome();
      } else {
        _selectTab(next[idx.clamp(0, next.length - 1)]);
      }
    }
  }

  Future<bool?> _confirmCloseWithSessions(int running) {
    final l10n = context.l10n;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.homeWorkspaceCloseProjectTitle),
        content: Text(l10n.homeWorkspaceCloseProjectMessage(running)),
        actions: [
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

    final cs = Theme.of(context).colorScheme;
    // Show every open project tab across all teams (IDE-style open editors).
    // Selecting a tab switches the active team to the project's team via
    // HomeWorkspaceProjectPage, so the sidebar/content stay in sync.
    final tabs = <HomeProjectTab>[
      for (final id in _openIds)
        if (_resolve(projects, id) case final p?)
          HomeProjectTab(
            id: id,
            name: p.effectiveDisplay,
            tooltip: _projectTabTooltip(p),
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
          backgroundColor: cs.workspacePage,
          body: Column(
            children: [
              HomeWorkspaceTitleBar(
            tabs: tabs,
            activeProjectId: activeId,
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

  static String _projectTabTooltip(AppProject project) {
    final name = project.effectiveDisplay;
    final path = project.primaryPath.trim();
    if (path.isEmpty || path == name) return name;
    return '$name\n$path';
  }
}
