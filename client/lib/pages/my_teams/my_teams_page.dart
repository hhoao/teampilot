import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/settings/workspace_hub_shell.dart';

/// Ownership surface for local [TeamProfile]s — list and actions land in later tasks.
class MyTeamsPage extends StatelessWidget {
  const MyTeamsPage({super.key});

  static const _pageKey = ValueKey('my-teams-workspace');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      key: _pageKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceHubTitleBar(
            title: l10n.myTeamsTitle,
            subtitle: l10n.myTeamsSubtitle,
          ),
          const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );
  }
}
