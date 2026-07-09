import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/settings/workspace_hub_shell.dart';

/// Ownership surface for local expert templates — list and actions land in later tasks.
class MyExpertsPage extends StatelessWidget {
  const MyExpertsPage({super.key});

  static const _pageKey = ValueKey('my-experts-workspace');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      key: _pageKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceHubTitleBar(
            title: l10n.myExpertsTitle,
            subtitle: l10n.myExpertsSubtitle,
          ),
          const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );
  }
}
