import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../utils/app_keys.dart';
import '../../widgets/settings/workspace_section_host.dart';
import 'automations_panel.dart';

/// Global automations management page embedded in [HomeGlobalSection].
class AutomationManagementPage extends StatelessWidget {
  const AutomationManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WorkspaceHubDesktopShell(
      pageKey: AppKeys.automationsWorkspace,
      title: l10n.automationsTitle,
      subtitle: l10n.automationsSubtitle,
      nav: const SizedBox.shrink(),
      body: const AutomationsPanel(groupByWorkspace: true, embedded: true),
    );
  }
}
