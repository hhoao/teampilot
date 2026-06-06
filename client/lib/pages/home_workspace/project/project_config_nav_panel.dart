import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../utils/debounce/debounce.dart';
import '../../../widgets/settings/workspace_hub_shell.dart';
import '../../../widgets/settings/workspace_section_host.dart';
import 'project_config_section.dart';

/// Middle nav column for project configuration (same role as [TeamConfigNavPanel]).
class ProjectConfigNavPanel extends StatelessWidget {
  const ProjectConfigNavPanel({
    required this.sections,
    required this.section,
    required this.onSelect,
    required this.l10n,
    this.onOpenTeamConfig,
    super.key,
  });

  final List<ProjectConfigSection> sections;
  final ProjectConfigSection section;
  final ValueChanged<ProjectConfigSection> onSelect;
  final AppLocalizations l10n;
  final VoidCallback? onOpenTeamConfig;

  @override
  Widget build(BuildContext context) {
    return WorkspaceCompositeNavPanel(
      primaryEntries: [
        for (final s in sections)
          WorkspaceHubEntry(
            title: s.title(l10n),
            icon: s.icon,
            selected: section == s,
            density: WorkspaceHubNavDensity.relaxed,
            onTap: throttledTap(
              'project_config_nav_${s.name}',
              () => onSelect(s),
            ),
          ),
      ],
      trailingChildren: [
        if (onOpenTeamConfig != null)
          WorkspaceHubNavItem(
            title: l10n.homeWorkspaceTeamConfig,
            icon: Icons.groups_outlined,
            trailingIcon: Icons.open_in_new_rounded,
            density: WorkspaceHubNavDensity.relaxed,
            onTap: throttledTap(
              'project_config_nav_team',
              onOpenTeamConfig!,
            ),
          ),
      ],
    );
  }
}
