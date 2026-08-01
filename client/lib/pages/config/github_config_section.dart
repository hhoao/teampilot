import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/github/github_device_flow_panel.dart';
import '../../widgets/settings/workspace_pane_header.dart';

class GithubConfigWorkspace extends StatelessWidget {
  const GithubConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) WorkspacePaneHeader(title: l10n.githubSettingsTitle),
        const Expanded(
          child: SingleChildScrollView(
            child: GithubDeviceFlowPanel(
              showAdvancedPat: true,
              showDisconnect: true,
            ),
          ),
        ),
      ],
    );
  }
}
