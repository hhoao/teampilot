import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';

/// Personal identity configuration tabs on the home workspace (not project manage).
enum HomeIdentityConfigSection {
  agent,
  skills,
  plugins,
  mcp,
  extensions;

  String title(AppLocalizations l10n) => switch (this) {
    HomeIdentityConfigSection.agent => l10n.homeWorkspaceWorkspaceAgent,
    HomeIdentityConfigSection.skills => l10n.homeWorkspaceWorkspaceSkills,
    HomeIdentityConfigSection.plugins => l10n.homeWorkspaceWorkspacePlugins,
    HomeIdentityConfigSection.mcp => l10n.homeWorkspaceWorkspaceMcp,
    HomeIdentityConfigSection.extensions => l10n.homeWorkspaceWorkspaceExtensions,
  };

  IconData get icon => switch (this) {
    HomeIdentityConfigSection.agent => Icons.smart_toy_outlined,
    HomeIdentityConfigSection.skills => Icons.extension_outlined,
    HomeIdentityConfigSection.plugins => Icons.widgets_outlined,
    HomeIdentityConfigSection.mcp => Icons.hub_outlined,
    HomeIdentityConfigSection.extensions => Icons.power_outlined,
  };
}
