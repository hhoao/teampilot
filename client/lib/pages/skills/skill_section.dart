import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/app/platform_utils.dart';
import '../../widgets/settings/workspace_section_navigation.dart';

enum SkillSection implements WorkspaceSectionDescriptor {
  installed,
  discovery,
  registries;

  @override
  String get routeSegment => name;

  @override
  String routePath(String basePath) => '$basePath/$routeSegment';

  @override
  String title(AppLocalizations l10n) => switch (this) {
    SkillSection.installed => l10n.skills.navInstalled,
    SkillSection.discovery => l10n.skills.navDiscovery,
    SkillSection.registries => l10n.skills.navRegistries,
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
  SkillSection.registries => Icons.source_outlined,
};
