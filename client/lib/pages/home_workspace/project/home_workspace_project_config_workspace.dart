import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_project.dart';
import '../../../utils/app_keys.dart';
import '../../../widgets/settings/workspace_section_host.dart';
import 'config/project_agent_section.dart';
import 'config/project_extensions_section.dart';
import 'config/project_mcp_section.dart';
import 'config/project_plugins_section.dart';
import 'config/project_skills_section.dart';
import 'project_config_nav_panel.dart';
import 'project_config_section.dart';
import 'project_info_section.dart';

/// Project configuration workspace — reuses the same shell as [TeamConfigPage].
class HomeWorkspaceProjectConfigWorkspace extends StatefulWidget {
  const HomeWorkspaceProjectConfigWorkspace({
    required this.project,
    required this.section,
    super.key,
  });

  final AppProject project;
  final ProjectConfigSection section;

  @override
  State<HomeWorkspaceProjectConfigWorkspace> createState() =>
      _HomeWorkspaceProjectConfigWorkspaceState();
}

class _HomeWorkspaceProjectConfigWorkspaceState
    extends State<HomeWorkspaceProjectConfigWorkspace> {
  String _managePath(ProjectConfigSection section) {
    final base = '/home-v2/project/${widget.project.projectId}';
    final params = <String, String>{
      'view': 'manage',
      'section': section.routeSegment,
    };
    return Uri(path: base, queryParameters: params).toString();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isPersonal = widget.project.teamId.isEmpty;
    final sections = isPersonal
        ? ProjectConfigSection.personalSections
        : ProjectConfigSection.teamSections;
    final section = sections.contains(widget.section)
        ? widget.section
        : ProjectConfigSection.settings;

    final body = switch (section) {
      ProjectConfigSection.settings => ProjectInfoSection(project: widget.project),
      ProjectConfigSection.agent => ProjectAgentSection(
          projectId: widget.project.projectId,
        ),
      ProjectConfigSection.skills => ProjectSkillsSection(
          projectId: widget.project.projectId,
        ),
      ProjectConfigSection.plugins => ProjectPluginsSection(
          projectId: widget.project.projectId,
        ),
      ProjectConfigSection.mcp => ProjectMcpSection(
          projectId: widget.project.projectId,
        ),
      ProjectConfigSection.extensions => ProjectExtensionsSection(
          projectId: widget.project.projectId,
        ),
    };

    return WorkspaceAdaptiveSectionPage(
      pageKey: AppKeys.projectConfigWorkspace,
      title: l10n.homeWorkspaceProjectManagement,
      subtitle: widget.project.effectiveDisplay,
      bodyAnimationKey: ValueKey(
        'project-config-body-${section.name}-${widget.project.projectId}',
      ),
      nav: ProjectConfigNavPanel(
        sections: sections,
        section: section,
        l10n: l10n,
        onSelect: (s) => context.go(_managePath(s)),
        onOpenTeamConfig: isPersonal
            ? null
            : () => context.go('/home-v2?section=members'),
      ),
      body: body,
    );
  }
}
