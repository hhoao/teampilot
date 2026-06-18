import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/identity_kind.dart';
import '../../../widgets/settings/workspace_section_navigation.dart';

/// Personal / team workspace configuration sections (mirrors [TeamConfigSection]).
enum WorkspaceConfigSection implements WorkspaceSectionDescriptor {
  settings,
  members,
  agent,
  skills,
  plugins,
  mcp,
  extensions;

  static const _bundleSections = [
    settings,
    agent,
    skills,
    plugins,
    mcp,
    extensions,
  ];

  static List<WorkspaceConfigSection> forKind(IdentityKind kind) =>
      kind == IdentityKind.team
          ? [...{_bundleSections.first}, members, ..._bundleSections.skip(1)]
          : _bundleSections;

  @override
  String get routeSegment => switch (this) {
        WorkspaceConfigSection.settings => 'settings',
        WorkspaceConfigSection.members => 'members',
        WorkspaceConfigSection.agent => 'agent',
        WorkspaceConfigSection.skills => 'skills',
        WorkspaceConfigSection.plugins => 'plugins',
        WorkspaceConfigSection.mcp => 'mcp',
        WorkspaceConfigSection.extensions => 'extensions',
      };

  @override
  String routePath(String basePath) => '$basePath?section=$routeSegment';

  @override
  String title(AppLocalizations l10n) => switch (this) {
        WorkspaceConfigSection.settings => l10n.homeWorkspaceWorkspaceSettings,
        WorkspaceConfigSection.members => l10n.homeWorkspaceWorkspaceMembers,
        WorkspaceConfigSection.agent => l10n.homeWorkspaceWorkspaceAgent,
        WorkspaceConfigSection.skills => l10n.homeWorkspaceWorkspaceSkills,
        WorkspaceConfigSection.plugins => l10n.homeWorkspaceWorkspacePlugins,
        WorkspaceConfigSection.mcp => l10n.homeWorkspaceWorkspaceMcp,
        WorkspaceConfigSection.extensions => l10n.homeWorkspaceWorkspaceExtensions,
      };

  @override
  IconData get icon => workspaceConfigSectionIcon(this);

  static WorkspaceConfigSection? fromSegment(String? segment) {
    final value = segment?.trim();
    if (value == null || value.isEmpty) return null;
    for (final section in values) {
      if (section.routeSegment == value) return section;
    }
    return null;
  }
}

IconData workspaceConfigSectionIcon(WorkspaceConfigSection section) =>
    switch (section) {
      WorkspaceConfigSection.settings => Icons.tune_outlined,
      WorkspaceConfigSection.members => Icons.person_outline,
      WorkspaceConfigSection.agent => Icons.smart_toy_outlined,
      WorkspaceConfigSection.skills => Icons.extension_outlined,
      WorkspaceConfigSection.plugins => Icons.widgets_outlined,
      WorkspaceConfigSection.mcp => Icons.hub_outlined,
      WorkspaceConfigSection.extensions => Icons.power_outlined,
    };
