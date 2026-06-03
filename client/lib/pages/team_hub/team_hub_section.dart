import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/settings/workspace_section_navigation.dart';

enum TeamHubSection implements WorkspaceSectionDescriptor {
  discovery,
  favorites;

  @override
  String get routeSegment => name;

  @override
  String routePath(String basePath) => '$basePath/$routeSegment';

  @override
  String title(AppLocalizations l10n) => switch (this) {
        TeamHubSection.discovery => l10n.teamHubDiscovery,
        TeamHubSection.favorites => l10n.teamHubFavorites,
      };

  @override
  IconData get icon => switch (this) {
        TeamHubSection.discovery => Icons.travel_explore_outlined,
        TeamHubSection.favorites => Icons.star_outline_rounded,
      };
}
