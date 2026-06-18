import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../cubits/launch_profile_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../models/personal_profile.dart';
import '../../../models/team_config.dart';
import '../../../models/launch_profile.dart';
import '../../../utils/app_keys.dart';
import '../../../utils/workspace_display_name.dart';
import '../../../widgets/settings/workspace_section_host.dart';
import '../home_workspace_global_section.dart';
import '../home_workspace_team_tab.dart';
import 'config/workspace_agent_section.dart';
import 'config/workspace_extensions_section.dart';
import 'config/workspace_mcp_section.dart';
import 'config/workspace_plugins_section.dart';
import 'config/workspace_skills_section.dart';
import 'workspace_config_nav_panel.dart';
import 'workspace_config_section.dart';
import 'workspace_info_section.dart';
import '../../team_config/team_config_info_section.dart';
import '../../team_config/team_config_section.dart';

/// Workspace configuration workspace — identity-driven sections for personal and
/// team launch identities.
class WorkspaceConfigPanel extends StatefulWidget {
  const WorkspaceConfigPanel({
    required this.workspace,
    required this.profileId,
    required this.section,
    super.key,
  });

  final Workspace workspace;
  final String profileId;
  final WorkspaceConfigSection section;

  @override
  State<WorkspaceConfigPanel> createState() =>
      _WorkspaceConfigPanelState();
}

class _WorkspaceConfigPanelState
    extends State<WorkspaceConfigPanel> {
  String _managePath(WorkspaceConfigSection section) {
    return Uri(
      path: '/home-v2/workspace/${widget.workspace.workspaceId}',
      queryParameters: {
        'as': widget.profileId,
        'view': 'manage',
        'section': section.routeSegment,
      },
    ).toString();
  }

  void _openGlobalView(HomeGlobalView view) {
    context.go(view.homeLocation);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final identity = context.select<LaunchProfileCubit, LaunchProfile?>(
      (c) => c.byId(widget.profileId),
    );
    if (identity == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final sections = WorkspaceConfigSection.forKind(identity.kind);
    final section = sections.contains(widget.section)
        ? widget.section
        : WorkspaceConfigSection.settings;
    final identityCubit = context.read<LaunchProfileCubit>();
    final team = identity is TeamProfile ? identity : null;

    final body = switch (section) {
      WorkspaceConfigSection.settings => WorkspaceInfoSection(workspace: widget.workspace),
      WorkspaceConfigSection.members when team != null => HomeTeamTab(
          section: TeamConfigSection.members,
          team: team,
          cubit: identityCubit,
        ),
      WorkspaceConfigSection.agent when identity is PersonalProfile =>
        WorkspaceAgentSection(
          workspaceId: widget.workspace.workspaceId,
          profileId: identity.id,
        ),
      WorkspaceConfigSection.agent when team != null => TeamInfoSection(
          team: team,
          cubit: identityCubit,
        ),
      WorkspaceConfigSection.skills when identity is PersonalProfile =>
        WorkspaceSkillsSection(
          workspaceId: widget.workspace.workspaceId,
          profileId: identity.id,
        ),
      WorkspaceConfigSection.skills when team != null => HomeTeamTab(
          section: TeamConfigSection.skills,
          team: team,
          cubit: identityCubit,
          onSelectGlobalView: _openGlobalView,
        ),
      WorkspaceConfigSection.plugins when identity is PersonalProfile =>
        WorkspacePluginsSection(
          workspaceId: widget.workspace.workspaceId,
          profileId: identity.id,
        ),
      WorkspaceConfigSection.plugins when team != null => HomeTeamTab(
          section: TeamConfigSection.plugins,
          team: team,
          cubit: identityCubit,
          onSelectGlobalView: _openGlobalView,
        ),
      WorkspaceConfigSection.mcp when identity is PersonalProfile =>
        WorkspaceMcpSection(
          workspaceId: widget.workspace.workspaceId,
          profileId: identity.id,
        ),
      WorkspaceConfigSection.mcp when team != null => HomeTeamTab(
          section: TeamConfigSection.mcp,
          team: team,
          cubit: identityCubit,
          onSelectGlobalView: _openGlobalView,
        ),
      WorkspaceConfigSection.extensions when identity is PersonalProfile =>
        WorkspaceExtensionsSection(workspaceId: widget.workspace.workspaceId),
      WorkspaceConfigSection.extensions when team != null => HomeTeamTab(
          section: TeamConfigSection.extensions,
          team: team,
          cubit: identityCubit,
        ),
      _ => const SizedBox.shrink(),
    };

    return WorkspaceAdaptiveSectionPage(
      pageKey: AppKeys.workspaceConfigWorkspace,
      title: l10n.homeWorkspaceWorkspaceManagement,
      subtitle: widget.workspace.localizedName(l10n),
      bodyAnimationKey: ValueKey(
        'workspace-config-body-${section.name}-${widget.workspace.workspaceId}-${identity.id}',
      ),
      nav: WorkspaceConfigNavPanel(
        sections: sections,
        section: section,
        l10n: l10n,
        onSelect: (s) => context.go(_managePath(s)),
      ),
      body: body,
    );
  }
}
