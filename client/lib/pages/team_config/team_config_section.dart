import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/settings/workspace_section_navigation.dart';

enum TeamConfigSection implements WorkspaceSectionDescriptor {
  team,
  skills,
  plugins,
  mcp,
  extensions,
  members;

  @override
  String get routeSegment => switch (this) {
        TeamConfigSection.team => 'team',
        TeamConfigSection.skills => 'skills',
        TeamConfigSection.plugins => 'plugins',
        TeamConfigSection.mcp => 'mcp',
        TeamConfigSection.extensions => 'extensions',
        TeamConfigSection.members => 'members',
      };

  @override
  String routePath(String basePath) => switch (this) {
        TeamConfigSection.members => '$basePath/members',
        _ => '$basePath/$routeSegment',
      };

  @override
  String title(AppLocalizations l10n) => switch (this) {
        TeamConfigSection.team => l10n.teamSettings,
        TeamConfigSection.skills => l10n.teamSkillsNav,
        TeamConfigSection.plugins => l10n.teamPluginsNav,
        TeamConfigSection.mcp => l10n.teamMcpNav,
        TeamConfigSection.extensions => l10n.teamExtensionsNav,
        TeamConfigSection.members => l10n.members,
      };

  @override
  IconData get icon => teamConfigSectionIcon(this);

  /// Resolves a [routeSegment] (e.g. `members`, `team`) back to a section;
  /// null for unknown/empty input. Used to deep-link the home workspace tabs.
  static TeamConfigSection? fromSegment(String? segment) {
    final value = segment?.trim();
    if (value == null || value.isEmpty) return null;
    for (final section in values) {
      if (section.routeSegment == value) return section;
    }
    return null;
  }
}

IconData teamConfigSectionIcon(TeamConfigSection section) => switch (section) {
      TeamConfigSection.team => Icons.groups_outlined,
      TeamConfigSection.skills => Icons.extension_outlined,
      TeamConfigSection.plugins => Icons.widgets_outlined,
      TeamConfigSection.mcp => Icons.hub_outlined,
      TeamConfigSection.extensions => Icons.power_outlined,
      TeamConfigSection.members => Icons.person_outline,
    };

String memberRoutePath(String basePath, String memberId) =>
    '$basePath/members/$memberId';
