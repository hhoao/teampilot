import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/identity_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_project.dart';
import '../../../models/identity_kind.dart';
import '../../../models/launch_identity.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace_identity.dart';
import '../../../services/storage/identity_provisioner.dart';
import '../../../theme/workspace_surface_layers.dart';
import 'home_workspace_project_config_workspace.dart';
import 'home_workspace_project_rail.dart';
import 'home_workspace_project_section.dart';
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
    this.identity,
    this.view,
    this.configSection,
    super.key,
  });

  final String projectId;

  /// Launch identity from `?as=`. Null means "no identity chosen" → the page
  /// redirects to the project grid.
  final LaunchIdentity? identity;

  /// `manage` opens [HomeWorkspaceProjectConfigWorkspace] (personal projects).
  final String? view;

  final ProjectConfigSection? configSection;

  @override
  State<HomeWorkspaceProjectPage> createState() =>
      _HomeWorkspaceProjectPageState();
}

class _HomeWorkspaceProjectPageState extends State<HomeWorkspaceProjectPage> {
  late HomeWorkspaceProjectSection _section = _sectionFromRoute();
  var _visitedManage = false;

  ProjectConfigSection get _configSection =>
      widget.configSection ?? ProjectConfigSection.settings;

  @override
  void initState() {
    super.initState();
    if (widget.view == 'manage') {
      _visitedManage = true;
    }
    context.read<ChatCubit>().setActiveProject(widget.projectId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncProjectContext());
  }

  @override
  void didUpdateWidget(covariant HomeWorkspaceProjectPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId ||
        oldWidget.identity != widget.identity) {
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

  WorkspaceIdentity? _resolveWorkspaceIdentity() {
    final launchIdentity = widget.identity;
    if (launchIdentity == null) return null;
    final cubit = context.read<IdentityCubit>();
    final resolved = cubit.byId(launchIdentity.identityId);
    if (resolved != null) return resolved;
    return cubit.byId(IdentityProvisioner.defaultPersonalId);
  }

  void _syncProjectContext() {
    if (!mounted) return;
    if (widget.identity == null) return;
    final project = _findProject(
      context.read<ChatCubit>().state.projects,
      widget.projectId,
    );
    if (project == null) return;
    final workspaceIdentity = _resolveWorkspaceIdentity();
    if (workspaceIdentity is TeamIdentity) {
      _syncSelectedTeam(workspaceIdentity.id);
    }
  }

  void _onSectionChanged(
    HomeWorkspaceProjectSection section,
    AppProject project,
    WorkspaceIdentity workspaceIdentity,
  ) {
    setState(() {
      _section = section;
      if (section == HomeWorkspaceProjectSection.manage) {
        _visitedManage = true;
      }
    });

    final base =
        '/home-v2/project/${project.projectId}?as=${workspaceIdentity.id}';
    final path = switch (section) {
      HomeWorkspaceProjectSection.conversations => base,
      HomeWorkspaceProjectSection.manage => '$base&view=manage',
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

    final launchIdentity = widget.identity;
    if (launchIdentity == null) {
      // No identity chosen (e.g. a hand-typed project URL). Bounce back to the
      // workspace home, which opens on the All Projects pane by default.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/home-v2');
      });
      return WorkspacePageCardShell(
        chrome: WorkspacePageChrome.project,
        child: const SizedBox.shrink(),
      );
    }

    final workspaceIdentity = context.select<IdentityCubit, WorkspaceIdentity?>(
      (c) {
        final resolved = c.byId(launchIdentity.identityId);
        if (resolved != null) return resolved;
        return c.byId(IdentityProvisioner.defaultPersonalId);
      },
    );
    if (workspaceIdentity == null) {
      return WorkspacePageCardShell(
        chrome: WorkspacePageChrome.project,
        child: _MissingProject(label: l10n.homeWorkspaceEmptyProjects),
      );
    }

    final isPersonal = workspaceIdentity.kind == IdentityKind.personal;
    final sessionTeamFilter =
        isPersonal ? '' : workspaceIdentity.id;
    final cardBody = _buildCardBody(
      project: project,
      workspaceIdentity: workspaceIdentity,
      sessionTeamFilter: sessionTeamFilter,
    );

    return _buildProjectPageWithRail(
      project: project,
      workspaceIdentity: workspaceIdentity,
      isPersonal: isPersonal,
      cardBody: cardBody,
    );
  }

  Widget _buildProjectPageWithRail({
    required AppProject project,
    required WorkspaceIdentity workspaceIdentity,
    required bool isPersonal,
    required Widget cardBody,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeWorkspaceProjectRail(
          section: _section,
          isPersonalProject: isPersonal,
          onSectionChanged: (section) =>
              _onSectionChanged(section, project, workspaceIdentity),
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

  Widget _buildCardBody({
    required AppProject project,
    required WorkspaceIdentity workspaceIdentity,
    required String sessionTeamFilter,
  }) {
    final showManage = _section == HomeWorkspaceProjectSection.manage;
    return IndexedStack(
      index: showManage ? 1 : 0,
      sizing: StackFit.expand,
      children: [
        HomeWorkspaceProjectSplitPane(
          key: ValueKey('conversations-${project.projectId}-${workspaceIdentity.id}'),
          project: project,
          isPersonalProject: workspaceIdentity.kind == IdentityKind.personal,
          identityId: workspaceIdentity.id,
          sessionTeamFilter: sessionTeamFilter,
        ),
        if (_visitedManage)
          HomeWorkspaceProjectConfigWorkspace(
            project: project,
            identityId: workspaceIdentity.id,
            section: _configSection,
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }

  void _syncSelectedTeam(String teamId) {
    if (teamId.isEmpty) return;
    final teamCubit = context.read<IdentityCubit>();
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
