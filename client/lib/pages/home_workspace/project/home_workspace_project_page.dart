import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/project_profile_cubit.dart';
import '../../../cubits/team_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_project.dart';
import '../../../theme/workspace_surface_layers.dart';
import 'home_workspace_project_config_workspace.dart';
import 'home_workspace_project_rail.dart';
import 'home_workspace_project_section.dart';
import 'home_workspace_project_settings_view.dart';
import 'home_workspace_project_split_pane.dart';
import 'project_config_section.dart';

/// Project work page.
///
/// Personal and team projects share the icon rail + floated card layout.
/// Personal [HomeWorkspaceProjectSection.manage] opens the config workspace
/// with in-page section nav; the rail only switches conversations vs manage.
class HomeWorkspaceProjectPage extends StatefulWidget {
  const HomeWorkspaceProjectPage({
    required this.projectId,
    this.view,
    this.configSection,
    super.key,
  });

  final String projectId;

  /// `manage` opens [HomeWorkspaceProjectConfigWorkspace] (personal projects).
  final String? view;

  final ProjectConfigSection? configSection;

  @override
  State<HomeWorkspaceProjectPage> createState() =>
      _HomeWorkspaceProjectPageState();
}

class _HomeWorkspaceProjectPageState extends State<HomeWorkspaceProjectPage> {
  late HomeWorkspaceProjectSection _section = _sectionFromRoute();

  ProjectConfigSection get _configSection =>
      widget.configSection ?? ProjectConfigSection.settings;

  @override
  void initState() {
    super.initState();
    context.read<ChatCubit>().setActiveProject(widget.projectId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncProjectContext());
  }

  @override
  void didUpdateWidget(covariant HomeWorkspaceProjectPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      context.read<ChatCubit>().setActiveProject(widget.projectId);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _syncProjectContext(),
      );
    }
    if (oldWidget.view != widget.view ||
        oldWidget.configSection != widget.configSection) {
      setState(() => _section = _sectionFromRoute());
    }
  }

  HomeWorkspaceProjectSection _sectionFromRoute() {
    if (widget.view == 'manage') {
      return HomeWorkspaceProjectSection.manage;
    }
    return HomeWorkspaceProjectSection.conversations;
  }

  void _syncProjectContext() {
    if (!mounted) return;
    final project = _findProject(
      context.read<ChatCubit>().state.projects,
      widget.projectId,
    );
    if (project == null) return;
    if (project.teamId.isEmpty) {
      _loadPersonalProfile(project.projectId);
      return;
    }
    _syncSelectedTeam(project.teamId);
  }

  void _loadPersonalProfile(String projectId) {
    final cubit = context.read<ProjectProfileCubit>();
    if (cubit.state.projectId == projectId &&
        cubit.state.status == ProjectProfileLoadStatus.ready) {
      return;
    }
    unawaited(cubit.load(projectId));
  }

  void _onSectionChanged(
    HomeWorkspaceProjectSection section,
    AppProject project,
  ) {
    setState(() => _section = section);
    if (project.teamId.isNotEmpty) return;

    final base = '/home-v2/project/${project.projectId}';
    final path = switch (section) {
      HomeWorkspaceProjectSection.conversations => base,
      HomeWorkspaceProjectSection.manage => '$base?view=manage',
      _ => base,
    };
    if (GoRouterState.of(context).uri.toString() != path) {
      context.go(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final project = context.select<ChatCubit, AppProject?>(
      (c) => _findProject(c.state.projects, widget.projectId),
    );

    if (project == null) {
      return WorkspacePageCardShell(
        chrome: WorkspacePageChrome.project,
        child: _MissingProject(label: l10n.homeWorkspaceEmptyProjects),
      );
    }

    final isPersonal = project.teamId.isEmpty;
    final cardBody = isPersonal
        ? _buildPersonalCardBody(project)
        : _buildTeamCardBody(project);

    return _buildProjectPageWithRail(
      project: project,
      isPersonal: isPersonal,
      cardBody: cardBody,
    );
  }

  Widget _buildProjectPageWithRail({
    required AppProject project,
    required bool isPersonal,
    required Widget cardBody,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeWorkspaceProjectRail(
          section: _section,
          isPersonalProject: isPersonal,
          onSectionChanged: (section) => _onSectionChanged(section, project),
          onLogoTap: () => context.go('/home-v2'),
        ),
        Expanded(
          child: WorkspacePageCardShell(
            chrome: WorkspacePageChrome.project,
            omitLeftPadding: true,
            child: cardBody,
          ),
        ),
      ],
    );
  }

  Widget _buildPersonalCardBody(AppProject project) {
    if (_section == HomeWorkspaceProjectSection.manage) {
      return HomeWorkspaceProjectConfigWorkspace(
        project: project,
        section: _configSection,
      );
    }
    return _buildPersonalConversations(project);
  }

  Widget _buildPersonalConversations(AppProject project) {
    return HomeWorkspaceProjectSplitPane(
      project: project,
      isPersonalProject: true,
    );
  }

  Widget _buildTeamCardBody(AppProject project) {
    if (_section == HomeWorkspaceProjectSection.conversations) {
      return HomeWorkspaceProjectSplitPane(
        project: project,
        isPersonalProject: false,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [HomeWorkspaceProjectSettingsView(project: project)],
    );
  }

  void _syncSelectedTeam(String teamId) {
    if (teamId.isEmpty) return;
    final teamCubit = context.read<TeamCubit>();
    if (teamCubit.state.selectedTeam?.id == teamId) return;
    if (teamCubit.state.selectedTeam?.id != teamId) {
      teamCubit.selectTeam(teamId);
    }
  }

  static AppProject? _findProject(List<AppProject> projects, String id) {
    for (final p in projects) {
      if (p.projectId == id) return p;
    }
    return null;
  }
}

class _MissingProject extends StatelessWidget {
  const _MissingProject({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
    );
  }
}
