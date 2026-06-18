import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../cubits/identity_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_project.dart';
import '../../../models/personal_identity.dart';
import '../../../models/workspace_identity.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace_identity.dart';
import '../../../utils/app_keys.dart';
import '../../../utils/project_display_name.dart';
import '../../../widgets/settings/workspace_section_host.dart';
import '../home_workspace_global_section.dart';
import '../home_workspace_team_tab.dart';
import 'config/project_agent_section.dart';
import 'config/project_extensions_section.dart';
import 'config/project_mcp_section.dart';
import 'config/project_plugins_section.dart';
import 'config/project_skills_section.dart';
import 'project_config_nav_panel.dart';
import 'project_config_section.dart';
import 'project_info_section.dart';
import '../../team_config/team_config_info_section.dart';
import '../../team_config/team_config_section.dart';

/// Project configuration workspace — identity-driven sections for personal and
/// team launch identities.
class HomeWorkspaceProjectConfigWorkspace extends StatefulWidget {
  const HomeWorkspaceProjectConfigWorkspace({
    required this.project,
    required this.identityId,
    required this.section,
    super.key,
  });

  final AppProject project;
  final String identityId;
  final ProjectConfigSection section;

  @override
  State<HomeWorkspaceProjectConfigWorkspace> createState() =>
      _HomeWorkspaceProjectConfigWorkspaceState();
}

class _HomeWorkspaceProjectConfigWorkspaceState
    extends State<HomeWorkspaceProjectConfigWorkspace> {
  String _managePath(ProjectConfigSection section) {
    return Uri(
      path: '/home-v2/project/${widget.project.projectId}',
      queryParameters: {
        'as': widget.identityId,
        'view': 'manage',
        'section': section.routeSegment,
      },
    ).toString();
  }

  void _openGlobalView(HomeWorkspaceGlobalView view) {
    context.go(view.homeLocation);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final identity = context.select<IdentityCubit, WorkspaceIdentity?>(
      (c) => c.byId(widget.identityId),
    );
    if (identity == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final sections = ProjectConfigSection.forKind(identity.kind);
    final section = sections.contains(widget.section)
        ? widget.section
        : ProjectConfigSection.settings;
    final identityCubit = context.read<IdentityCubit>();
    final team = identity is TeamIdentity ? identity : null;

    final body = switch (section) {
      ProjectConfigSection.settings => ProjectInfoSection(project: widget.project),
      ProjectConfigSection.members when team != null => HomeWorkspaceTeamTab(
          section: TeamConfigSection.members,
          team: team,
          cubit: identityCubit,
        ),
      ProjectConfigSection.agent when identity is PersonalIdentity =>
        ProjectAgentSection(
          projectId: widget.project.projectId,
          identityId: identity.id,
        ),
      ProjectConfigSection.agent when team != null => TeamInfoSection(
          team: team,
          cubit: identityCubit,
        ),
      ProjectConfigSection.skills when identity is PersonalIdentity =>
        ProjectSkillsSection(
          projectId: widget.project.projectId,
          identityId: identity.id,
        ),
      ProjectConfigSection.skills when team != null => HomeWorkspaceTeamTab(
          section: TeamConfigSection.skills,
          team: team,
          cubit: identityCubit,
          onSelectGlobalView: _openGlobalView,
        ),
      ProjectConfigSection.plugins when identity is PersonalIdentity =>
        ProjectPluginsSection(
          projectId: widget.project.projectId,
          identityId: identity.id,
        ),
      ProjectConfigSection.plugins when team != null => HomeWorkspaceTeamTab(
          section: TeamConfigSection.plugins,
          team: team,
          cubit: identityCubit,
          onSelectGlobalView: _openGlobalView,
        ),
      ProjectConfigSection.mcp when identity is PersonalIdentity =>
        ProjectMcpSection(
          projectId: widget.project.projectId,
          identityId: identity.id,
        ),
      ProjectConfigSection.mcp when team != null => HomeWorkspaceTeamTab(
          section: TeamConfigSection.mcp,
          team: team,
          cubit: identityCubit,
          onSelectGlobalView: _openGlobalView,
        ),
      ProjectConfigSection.extensions when identity is PersonalIdentity =>
        ProjectExtensionsSection(projectId: widget.project.projectId),
      ProjectConfigSection.extensions when team != null => HomeWorkspaceTeamTab(
          section: TeamConfigSection.extensions,
          team: team,
          cubit: identityCubit,
        ),
      _ => const SizedBox.shrink(),
    };

    return WorkspaceAdaptiveSectionPage(
      pageKey: AppKeys.projectConfigWorkspace,
      title: l10n.homeWorkspaceProjectManagement,
      subtitle: widget.project.localizedName(l10n),
      bodyAnimationKey: ValueKey(
        'project-config-body-${section.name}-${widget.project.projectId}-${identity.id}',
      ),
      nav: ProjectConfigNavPanel(
        sections: sections,
        section: section,
        l10n: l10n,
        onSelect: (s) => context.go(_managePath(s)),
      ),
      body: body,
    );
  }
}
