import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/app/platform_utils.dart';
import '../../widgets/settings/workspace_section_navigation.dart';

/// Sections of the global Extensions management page. Extensions ship as a
/// fixed manifest catalog, so there is a single Installed section for now.
enum ExtensionSection implements WorkspaceSectionDescriptor {
  installed;

  @override
  String get routeSegment => name;

  @override
  String routePath(String basePath) => '$basePath/$routeSegment';

  @override
  String title(AppLocalizations l10n) => switch (this) {
    ExtensionSection.installed => l10n.extensionsNavInstalled,
  };

  @override
  IconData get icon => extensionSectionIcon(this);
}

void navigateExtensionSection(BuildContext context, ExtensionSection target) {
  navigateWorkspaceRoute(context, target.routePath('/extensions'));
}

IconData extensionSectionIcon(ExtensionSection section) => switch (section) {
  ExtensionSection.installed => Icons.power_outlined,
};
