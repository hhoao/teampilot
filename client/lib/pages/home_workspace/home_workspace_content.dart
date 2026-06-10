import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../services/home_workspace/home_workspace_project_display_prefs_store.dart';
import '../../services/home_workspace/home_workspace_project_favorites_store.dart';
import 'home_workspace_project_sort.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_project.dart';
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../theme/workspace_surface_layers.dart';
import '../team_config/team_config_section.dart';
import 'home_workspace_content_header.dart';
import 'home_workspace_global_section.dart';
import 'home_workspace_projects_tab.dart';
import 'home_workspace_team_tab.dart';

/// Right-hand content pane: team header, mapped tab bar (Projects / Resources /
/// Members / Skills & Plugins / Settings), a toolbar, and the project grid for
/// the selected team. Read-only — actions show a "coming soon" hint.
class HomeWorkspaceContent extends StatefulWidget {
  const HomeWorkspaceContent({
    this.initialSection,
    this.initialMemberId,
    this.onSelectGlobalView,
    super.key,
  });

  /// Team-config tab to select on first build; null shows the Projects tab.
  final TeamConfigSection? initialSection;

  /// Member to focus when [initialSection] is [TeamConfigSection.members].
  final String? initialMemberId;

  /// Switches the workspace right pane to a global management view, used by the
  /// embedded team skills/plugins/MCP tabs to jump to global management.
  final ValueChanged<HomeWorkspaceGlobalView>? onSelectGlobalView;

  @override
  State<HomeWorkspaceContent> createState() => _HomeWorkspaceContentState();
}

class _HomeWorkspaceContentState extends State<HomeWorkspaceContent> {
  final _projectFavoritesStore = HomeWorkspaceProjectFavoritesStore();
  final _displayPrefsStore = HomeWorkspaceProjectDisplayPrefsStore();
  Set<String> _favoriteProjectIds = {};

  // Tab 0 is Projects; the rest reuse the existing team-config sections in the
  // order the user requested: Members, Skills, Plugins, MCP, Extensions, Team.
  static const _sections = <TeamConfigSection?>[
    null,
    TeamConfigSection.members,
    TeamConfigSection.skills,
    TeamConfigSection.plugins,
    TeamConfigSection.mcp,
    TeamConfigSection.extensions,
    TeamConfigSection.team,
  ];

  late int _tabIndex = _initialTabIndex();
  var _gridView = true;
  var _projectSort = HomeWorkspaceProjectSort.recentlyUpdated;
  List<AppProject>? _lastAllProjects;
  String? _lastTeamId;
  List<AppProject>? _teamProjects;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProjectFavorites());
    unawaited(_loadDisplayPrefs());
  }

  Future<void> _loadProjectFavorites() async {
    final ids = await _projectFavoritesStore.load();
    if (!mounted) return;
    setState(() => _favoriteProjectIds = ids);
  }

  Future<void> _loadDisplayPrefs() async {
    final prefs = await _displayPrefsStore.load();
    if (!mounted) return;
    setState(() {
      _gridView = prefs.gridView;
      _projectSort = prefs.sort;
    });
  }

  Future<void> _setGridView(bool gridView) async {
    setState(() => _gridView = gridView);
    await _displayPrefsStore.save(
      HomeWorkspaceProjectDisplayPrefs(gridView: gridView, sort: _projectSort),
    );
  }

  Future<void> _setProjectSort(HomeWorkspaceProjectSort sort) async {
    setState(() => _projectSort = sort);
    await _displayPrefsStore.save(
      HomeWorkspaceProjectDisplayPrefs(gridView: _gridView, sort: sort),
    );
  }

  Future<void> _toggleProjectFavorite(String projectId) async {
    final nowOn = await _projectFavoritesStore.toggle(projectId);
    if (!mounted) return;
    setState(() {
      final next = {..._favoriteProjectIds};
      if (nowOn) {
        next.add(projectId);
      } else {
        next.remove(projectId);
      }
      _favoriteProjectIds = next;
    });
  }

  int _initialTabIndex() {
    final section = widget.initialSection;
    if (section == null) return 0;
    final index = _sections.indexOf(section);
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final teamCubit = context.watch<TeamCubit>();
    final team = teamCubit.state.selectedTeam;

    final projects = context.select<ChatCubit, List<AppProject>>(
      (c) => c.state.projects,
    );
    final sessions = context.select<ChatCubit, List<AppSession>>(
      (c) => c.state.sessions,
    );

    if (team == null) {
      return ColoredBox(
        color: cs.surface,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final teamProjects = _projectsForTeam(team, projects);
    final tabs = <String>[
      l10n.homeWorkspaceTeamProjects,
      for (final section in _sections.skip(1)) section!.title(l10n),
    ];
    final activeSection = _sections[_tabIndex];

    return ColoredBox(
      color: cs.workspaceCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeWorkspaceTeamHeader(team: team),
          const SizedBox(height: 14),
          HomeWorkspaceContentTabBar(
            tabs: tabs,
            selectedIndex: _tabIndex,
            onSelect: (i) => setState(() => _tabIndex = i),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Expanded(
            child:
                (activeSection == null
                        ? HomeWorkspaceProjectsTab(
                            projects: teamProjects,
                            sessions: sessions,
                            gridView: _gridView,
                            onToggleView: _setGridView,
                            projectSort: _projectSort,
                            onProjectSortChanged: _setProjectSort,
                            favoriteProjectIds: _favoriteProjectIds,
                            onToggleProjectFavorite: _toggleProjectFavorite,
                          )
                        : HomeWorkspaceTeamTab(
                            key: ValueKey(
                              'home-team-tab-${activeSection.name}',
                            ),
                            section: activeSection,
                            team: team,
                            cubit: teamCubit,
                            initialMemberId:
                                activeSection == TeamConfigSection.members
                                ? widget.initialMemberId
                                : null,
                            onSelectGlobalView: widget.onSelectGlobalView,
                          ))
                    // Match the global-navigation section transition: fade + slight
                    // slide-in, replayed whenever the selected tab changes.
                    .animate(key: ValueKey('home-content-tab-$_tabIndex'))
                    .fadeIn(duration: 180.ms, curve: Curves.easeOut)
                    .slideX(
                      begin: 0.025,
                      end: 0,
                      duration: 220.ms,
                      curve: Curves.easeOutCubic,
                    ),
          ),
        ],
      ),
    );
  }

  List<AppProject> _projectsForTeam(
    TeamConfig team,
    List<AppProject> projects,
  ) {
    if (identical(projects, _lastAllProjects) && team.id == _lastTeamId) {
      return _teamProjects!;
    }
    _lastAllProjects = projects;
    _lastTeamId = team.id;
    _teamProjects = projects.where((p) => p.teamId == team.id).toList();
    return _teamProjects!;
  }
}
