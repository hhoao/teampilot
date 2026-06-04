import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import 'log_viewer_panel.dart';

/// Logs section inside [ConfigWorkspace] (settings split layout + padding).
class LogConfigWorkspace extends StatelessWidget {
  const LogConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) ...[
          WorkspaceSectionHeading(
            title: l10n.logViewerTitle,
            subtitle: l10n.logViewerSubtitle,
          ),
          const SizedBox(height: 16),
        ],
        const Expanded(child: LogViewerPanel()),
      ],
    );
  }
}

/// Standalone shell (e.g. startup error flow).
class LogViewerPage extends StatelessWidget {
  const LogViewerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.logViewerTitle)),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: const LogConfigWorkspace(),
      ),
    );
  }
}
