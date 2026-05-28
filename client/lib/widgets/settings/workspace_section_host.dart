import 'package:flutter/material.dart';

import '../../services/app/platform_utils.dart';
import '../../theme/workspace_surface_layers.dart';
import 'workspace_hub_shell.dart';

class WorkspaceHubDesktopShell extends StatelessWidget {
  const WorkspaceHubDesktopShell({
    required this.title,
    required this.subtitle,
    required this.nav,
    required this.body,
    this.bodyAnimationKey,
    this.pageKey,
    super.key,
  });

  final Key? pageKey;
  final String title;
  final String subtitle;
  final Widget nav;
  final Widget body;
  final Key? bodyAnimationKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: pageKey,
      color: cs.workspacePage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceHubTitleBar(title: title, subtitle: subtitle),
          Expanded(
            child: WorkspaceSplitShell(
              bodyAnimationKey: bodyAnimationKey,
              nav: nav,
              body: body,
            ),
          ),
        ],
      ),
    );
  }
}

class WorkspaceAdaptiveSectionPage extends StatelessWidget {
  const WorkspaceAdaptiveSectionPage({
    required this.pageKey,
    required this.title,
    required this.subtitle,
    required this.nav,
    required this.body,
    this.bodyAnimationKey,
    super.key,
  });

  final Key pageKey;
  final String title;
  final String subtitle;
  final Widget nav;
  final Widget body;
  final Key? bodyAnimationKey;

  @override
  Widget build(BuildContext context) {
    if (useAndroidHubNavigation(context)) {
      return WorkspaceSectionPage(pageKey: pageKey, child: body);
    }
    return WorkspaceHubDesktopShell(
      pageKey: pageKey,
      title: title,
      subtitle: subtitle,
      bodyAnimationKey: bodyAnimationKey,
      nav: nav,
      body: body,
    );
  }
}
