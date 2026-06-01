import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/app/platform_utils.dart';
import '../../widgets/settings/workspace_section_navigation.dart';

enum PluginSection implements WorkspaceSectionDescriptor {
  installed,
  discovery,
  marketplaces;

  @override
  String get routeSegment => name;

  @override
  String routePath(String basePath) => '$basePath/$routeSegment';

  @override
  String title(AppLocalizations l10n) => switch (this) {
    PluginSection.installed => l10n.pluginsNavInstalled,
    PluginSection.discovery => l10n.pluginsNavDiscovery,
    PluginSection.marketplaces => l10n.pluginsNavMarketplaces,
  };

  @override
  IconData get icon => pluginSectionIcon(this);
}

void navigatePluginSection(BuildContext context, PluginSection target) {
  navigateWorkspaceRoute(context, target.routePath('/plugins'));
}

IconData pluginSectionIcon(PluginSection section) => switch (section) {
  PluginSection.installed => Icons.extension_outlined,
  PluginSection.discovery => Icons.travel_explore_outlined,
  PluginSection.marketplaces => Icons.store_outlined,
};
