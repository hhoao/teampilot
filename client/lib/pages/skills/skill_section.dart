import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/app/platform_utils.dart';
import '../../widgets/settings/workspace_section_navigation.dart';

enum SkillSection implements WorkspaceSectionDescriptor {
  installed,
  discovery,
  repos;

  @override
  String get routeSegment => name;

  @override
  String routePath(String basePath) => '$basePath/$routeSegment';

  @override
  String title(AppLocalizations l10n) => switch (this) {
    SkillSection.installed => l10n.skillsNavInstalled,
    SkillSection.discovery => l10n.skillsNavDiscovery,
    SkillSection.repos => l10n.skillsNavRepos,
  };

  @override
  IconData get icon => skillSectionIcon(this);
}

void navigateSkillSection(BuildContext context, SkillSection target) {
  navigateWorkspaceRoute(context, target.routePath('/skills'));
}

IconData skillSectionIcon(SkillSection section) => switch (section) {
  SkillSection.installed => Icons.inventory_2_outlined,
  SkillSection.discovery => Icons.travel_explore_outlined,
  SkillSection.repos => Icons.source_outlined,
};

