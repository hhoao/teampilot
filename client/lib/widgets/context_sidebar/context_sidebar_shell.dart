part of '../context_sidebar.dart';

class ContextSidebar extends StatefulWidget {
  const ContextSidebar({this.onNewProject, super.key});

  final VoidCallback? onNewProject;

  @override
  State<ContextSidebar> createState() => _ContextSidebarState();
}

class _ContextSidebarState extends State<ContextSidebar> {
  var _showSessions = false;
  String? _selectedProjectId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _showSessions = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final teamCubit = context.watch<TeamCubit>();
    final selected = teamCubit.state.selectedTeam;
    final projects = context.select<ChatCubit, List<AppProject>>(
      (cubit) => cubit.state.visibleProjects,
    );
    final sessions = context.select<ChatCubit, List<AppSession>>(
      (cubit) => cubit.state.visibleSessions,
    );
    final sortedProjects = _sortedProjects(projects, sessions);
    final selectedProject = _resolveSelectedProject(
      sortedProjects,
      sessions,
      _selectedProjectId,
    );

    return Container(
      key: AppKeys.contextSidebar,
      width: double.infinity,
      color: cs.surfaceContainer,
      padding: const EdgeInsets.all(13),
      child: selected == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TeamSelector(
                  teams: teamCubit.state.teams,
                  selected: selected,
                  onSelect: (id) => unawaited(teamCubit.selectTeam(id)),
                  onAddTeam: () => _promptAddTeam(context, teamCubit),
                ),
                const SizedBox(height: 14),
                _TeamConfigTile(
                  onTap: throttledTap(
                    'context_sidebar_team_config',
                    () => goFromSidebar(context, '/team-config'),
                  ),
                ),
                _NewChatTile(
                  onTap: throttledAsync(
                    'context_sidebar_new_chat',
                    () => _startNewChat(
                      context,
                      preferredProjectId: selectedProject?.projectId,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _showSessions
                      ? _ProjectSelector(
                          projects: sortedProjects,
                          selected: selectedProject,
                          sessions: sessions,
                          onSelect: (project) => setState(
                            () => _selectedProjectId = project.projectId,
                          ),
                          onNewProject: widget.onNewProject,
                        )
                      : const SizedBox.shrink(),
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                _SettingsTile(
                  onTap: throttledTap(
                    'context_sidebar_settings',
                    () => goFromSidebar(
                      context,
                      Platform.isAndroid ? '/config' : '/config/layout',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Most recently touched session time for a project (for ordering).
int _projectRecency(AppProject project, List<AppSession> allSessions) {
  var max = project.updatedAt;
  for (final s in allSessions) {
    if (s.projectId != project.projectId) continue;
    final t = s.updatedAt != 0 ? s.updatedAt : s.createdAt;
    if (t > max) max = t;
  }
  return max;
}

List<AppSession> _sessionsForProject(AppProject project, List<AppSession> all) {
  final byId = {for (final s in all) s.sessionId: s};
  final ordered = <AppSession>[];
  for (final id in project.sessionIds) {
    final s = byId[id];
    if (s != null) ordered.add(s);
  }
  for (final s in all) {
    if (s.projectId != project.projectId) continue;
    if (ordered.any((x) => x.sessionId == s.sessionId)) continue;
    ordered.add(s);
  }
  return ordered;
}
