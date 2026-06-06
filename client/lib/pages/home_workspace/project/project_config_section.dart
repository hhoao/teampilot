import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../widgets/settings/workspace_section_navigation.dart';

/// Personal / team project configuration sections (mirrors [TeamConfigSection]).
enum ProjectConfigSection implements WorkspaceSectionDescriptor {
  settings,
  agent,
  skills,
  plugins,
  mcp,
  extensions;

  static const personalSections = ProjectConfigSection.values;

  static const teamSections = <ProjectConfigSection>[settings];

  @override
  String get routeSegment => switch (this) {
        ProjectConfigSection.settings => 'settings',
        ProjectConfigSection.agent => 'agent',
        ProjectConfigSection.skills => 'skills',
        ProjectConfigSection.plugins => 'plugins',
        ProjectConfigSection.mcp => 'mcp',
        ProjectConfigSection.extensions => 'extensions',
      };

  @override
  String routePath(String basePath) => '$basePath?section=$routeSegment';

  @override
  String title(AppLocalizations l10n) => switch (this) {
        ProjectConfigSection.settings => l10n.homeWorkspaceProjectSettings,
        ProjectConfigSection.agent => l10n.homeWorkspaceProjectAgent,
        ProjectConfigSection.skills => l10n.homeWorkspaceProjectSkills,
        ProjectConfigSection.plugins => l10n.homeWorkspaceProjectPlugins,
        ProjectConfigSection.mcp => l10n.homeWorkspaceProjectMcp,
        ProjectConfigSection.extensions => l10n.homeWorkspaceProjectExtensions,
      };

  @override
  IconData get icon => projectConfigSectionIcon(this);

  static ProjectConfigSection? fromSegment(String? segment) {
    final value = segment?.trim();
    if (value == null || value.isEmpty) return null;
    for (final section in values) {
      if (section.routeSegment == value) return section;
    }
    return null;
  }
}

IconData projectConfigSectionIcon(ProjectConfigSection section) =>
    switch (section) {
      ProjectConfigSection.settings => Icons.tune_outlined,
      ProjectConfigSection.agent => Icons.smart_toy_outlined,
      ProjectConfigSection.skills => Icons.extension_outlined,
      ProjectConfigSection.plugins => Icons.widgets_outlined,
      ProjectConfigSection.mcp => Icons.hub_outlined,
      ProjectConfigSection.extensions => Icons.power_outlined,
    };
