import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_dialog_theme.dart';
import '../../theme/app_icon_sizes.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
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
      final cs = Theme.of(dialogContext).colorScheme;

      return AppDialog(
        maxWidth: width,
        maxHeight: height,
        contentPadding: EdgeInsets.zero,
        backgroundColor: cs.workspacePage,
        child: SizedBox(
          width: width,
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LogViewerDialogHeader(
                  title: l10n.logViewerTitle,
                  subtitle: l10n.logViewerSubtitle,
                  onClose: () => Navigator.of(dialogContext).pop(),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: const LogViewerPanel(useSurfaceCard: false),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _LogViewerDialogHeader extends StatelessWidget {
  const _LogViewerDialogHeader({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.subtitle.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: onClose,
            icon: Icon(Icons.close, size: context.appIconSizes.md),
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
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
