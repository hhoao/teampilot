import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_dialog_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import 'log_viewer_panel.dart';

const double _kLogViewerDialogWidth = 920;
const double _kLogViewerDialogHeight = 640;

/// Modal log viewer — used from settings/about instead of a full-page route.
Future<void> showLogViewerDialog(BuildContext context) {
  final l10n = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final media = MediaQuery.of(dialogContext);
      final width = _kLogViewerDialogWidth.clamp(
        0.0,
        media.size.width - kAppDialogInsetExtent,
      );
      final height = _kLogViewerDialogHeight.clamp(
        0.0,
        media.size.height - kAppDialogInsetExtent,
      );

      return AppDialog(
        maxWidth: width,
        maxHeight: height,
        contentPadding: EdgeInsets.zero,
        child: SizedBox(
          width: width,
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogHeader(
                title: l10n.logViewerTitle,
                onClose: () => Navigator.of(dialogContext).pop(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: const LogViewerPanel(),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

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
