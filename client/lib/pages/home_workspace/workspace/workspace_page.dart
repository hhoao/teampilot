import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../models/launch_profile_kind.dart';
import '../../../models/launch_profile_ref.dart';
import '../../../models/team_config.dart';
import '../../../models/launch_profile.dart';
import '../../../services/storage/launch_profile_provisioner.dart';
import '../../../theme/workspace_surface_layers.dart';
import 'workspace_config_workspace.dart';
import 'workspace_rail.dart';
import 'workspace_section.dart';
import 'workspace_split_pane.dart';
import 'workspace_config_section.dart';

/// Workspace work page.
///
/// Personal and team workspaces share the icon rail + floated card layout.
/// Personal [WorkspaceSection.manage] opens the config workspace
/// with in-page section nav; the rail only switches conversations vs manage.
class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    required this.workspaceId,
    this.identity,
    this.view,
    this.configSection,
    required this.routeActive,
    super.key,
  });

  final String workspaceId;

  /// Launch identity from `?as=`. Null means "no identity chosen" → the page
  /// redirects to the workspace grid.
  final LaunchProfileRef? identity;

  /// `manage` opens [WorkspaceConfigPanel] (personal workspaces).
  final String? view;

  final WorkspaceConfigSection? configSection;

  /// True when this page matches the current route (see [HomeWorkspaceBodyStack]).
  /// Only the active page may call [ChatCubit.setActiveWorkspace].
  final bool routeActive;

  @override
  State<WorkspacePage> createState() =>
      _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  late WorkspaceSection _section = _sectionFromRoute();
  var _visitedManage = false;

  WorkspaceConfigSection get _configSection =>
      widget.configSection ?? WorkspaceConfigSection.settings;

  @override
  void initState() {
    super.initState();
    if (widget.view == 'manage') {
      _visitedManage = true;
    }
    if (widget.routeActive) {
      context.read<ChatCubit>().setActiveWorkspace(widget.workspaceId);
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncWorkspaceContext());
    }
  }

  @override
  void didUpdateWidget(covariant WorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameActive = widget.routeActive && !oldWidget.routeActive;
    if (becameActive ||
        (widget.routeActive &&
            (oldWidget.workspaceId != widget.workspaceId ||
                oldWidget.identity != widget.identity))) {
      context.read<ChatCubit>().setActiveWorkspace(widget.workspaceId);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _syncWorkspaceContext(),
      );
    }
    if (widget.routeActive &&
        (oldWidget.view != widget.view ||
            oldWidget.configSection != widget.configSection)) {
      setState(() => _section = _sectionFromRoute());
    }
  }

  WorkspaceSection _sectionFromRoute() {
    if (widget.view == 'manage') {
      return WorkspaceSection.manage;
    }
    return WorkspaceSection.conversations;
  }

  LaunchProfile? _resolveIdentity() {
    final launchIdentity = widget.identity;
    if (launchIdentity == null) return null;
    final cubit = context.read<LaunchProfileCubit>();
    final resolved = cubit.byId(launchIdentity.profileId);
    if (resolved != null) return resolved;
    return cubit.byId(LaunchProfileProvisioner.defaultPersonalId);
  }

  void _syncWorkspaceContext() {
    if (!mounted) return;
    if (widget.identity == null) return;
    final workspace = _findWorkspace(
      context.read<ChatCubit>().state.workspaces,
      widget.workspaceId,
    );
    if (workspace == null) return;
    final workspaceIdentity = _resolveIdentity();
    if (workspaceIdentity is TeamProfile) {
      _syncSelectedTeam(workspaceIdentity.id);
    }
  }

  void _onSectionChanged(
    WorkspaceSection section,
    Workspace workspace,
    LaunchProfile workspaceIdentity,
  ) {
    setState(() {
      _section = section;
      if (section == WorkspaceSection.manage) {
        _visitedManage = true;
      }
    });

    final base =
        '/home-v2/workspace/${workspace.workspaceId}?as=${workspaceIdentity.id}';
    final path = switch (section) {
      WorkspaceSection.conversations => base,
      WorkspaceSection.manage => '$base&view=manage',
      _ => base,
    };
    if (GoRouterState.of(context).uri.toString() != path) {
      context.go(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final workspace = context.select<ChatCubit, Workspace?>(
      (c) => _findWorkspace(c.state.workspaces, widget.workspaceId),
    );

    if (workspace == null) {
      return WorkspacePageCardShell(
        chrome: WorkspacePageChrome.workspace,
        child: _MissingWorkspace(label: l10n.homeWorkspaceEmptyWorkspaces),
      );
    }

    final launchIdentity = widget.identity;
    if (launchIdentity == null) {
      // No identity chosen (e.g. a hand-typed workspace URL). Bounce back to the
      // workspace home, which opens on the All Workspaces pane by default.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/home-v2');
      });
      return WorkspacePageCardShell(
        chrome: WorkspacePageChrome.workspace,
        child: const SizedBox.shrink(),
      );
    }

    final workspaceIdentity = context.select<LaunchProfileCubit, LaunchProfile?>(
      (c) {
        final resolved = c.byId(launchIdentity.profileId);
        if (resolved != null) return resolved;
        return c.byId(LaunchProfileProvisioner.defaultPersonalId);
      },
    );
    if (workspaceIdentity == null) {
      return WorkspacePageCardShell(
        chrome: WorkspacePageChrome.workspace,
        child: _MissingWorkspace(label: l10n.homeWorkspaceEmptyWorkspaces),
      );
    }

    final isPersonal = workspaceIdentity.kind == LaunchProfileKind.personal;
    final sessionTeamFilter =
        isPersonal ? '' : workspaceIdentity.id;
    final cardBody = _buildCardBody(
      workspace: workspace,
      workspaceIdentity: workspaceIdentity,
      sessionTeamFilter: sessionTeamFilter,
    );

    return _buildWorkspacePageWithRail(
      workspace: workspace,
      workspaceIdentity: workspaceIdentity,
      isPersonal: isPersonal,
      cardBody: cardBody,
    );
  }

  Widget _buildWorkspacePageWithRail({
    required Workspace workspace,
    required LaunchProfile workspaceIdentity,
    required bool isPersonal,
    required Widget cardBody,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspaceRail(
          section: _section,
          isPersonalWorkspace: isPersonal,
          onSectionChanged: (section) =>
              _onSectionChanged(section, workspace, workspaceIdentity),
          onLogoTap: () => context.go('/home-v2'),
        ),
        Expanded(
          child: WorkspacePageCardShell(
            chrome: WorkspacePageChrome.workspace,
            omitLeftPadding: true,
            child: cardBody,
          ),
        ),
      ],
    );
  }

  Widget _buildCardBody({
    required Workspace workspace,
    required LaunchProfile workspaceIdentity,
    required String sessionTeamFilter,
  }) {
    final showManage = _section == WorkspaceSection.manage;
    return IndexedStack(
      index: showManage ? 1 : 0,
      sizing: StackFit.expand,
      children: [
        WorkspaceSplitPane(
          key: ValueKey('conversations-${workspace.workspaceId}-${workspaceIdentity.id}'),
          workspace: workspace,
          isPersonalWorkspace: workspaceIdentity.kind == LaunchProfileKind.personal,
          profileId: workspaceIdentity.id,
          sessionTeamFilter: sessionTeamFilter,
        ),
        if (_visitedManage)
          WorkspaceConfigPanel(
            workspace: workspace,
            profileId: workspaceIdentity.id,
            section: _configSection,
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }

  void _syncSelectedTeam(String teamId) {
    if (teamId.isEmpty) return;
    final teamCubit = context.read<LaunchProfileCubit>();
    if (teamCubit.state.selectedTeam?.id == teamId) return;
    if (teamCubit.state.selectedTeam?.id != teamId) {
      teamCubit.selectTeam(teamId);
    }
  }

  static Workspace? _findWorkspace(List<Workspace> workspaces, String id) {
    for (final p in workspaces) {
      if (p.workspaceId == id) return p;
    }
    return null;
  }
}

class _MissingWorkspace extends StatelessWidget {
  const _MissingWorkspace({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
    );
  }
}
