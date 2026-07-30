import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/progress_activity.dart';
import '../../services/progress_activity/progress_fraction.dart';

IconData progressActivityKindIcon(ProgressActivityKind kind) => switch (kind) {
  ProgressActivityKind.fileTreeImport => Icons.drive_file_move_outlined,
  ProgressActivityKind.appUpdate => Icons.system_update_alt_outlined,
  ProgressActivityKind.hubClone => Icons.cloud_download_outlined,
  ProgressActivityKind.packAcquire => Icons.inventory_2_outlined,
  ProgressActivityKind.cliProvision => Icons.terminal_outlined,
};

/// Ongoing progress row for the notification center.
class ProgressActivityTile extends StatelessWidget {
  const ProgressActivityTile({
    required this.activity,
    required this.onTap,
    required this.onCancel,
    super.key,
  });

  final ProgressActivity activity;
  final VoidCallback onTap;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;
    final fraction = resolveProgressFraction(activity);
    final isCancelling = activity.phase == ProgressActivityPhase.cancelling;
    final canCancel = activity.cancellable && !isCancelling;
    final subtitle = activity.subtitle?.trim();

    Widget progressBar;
    if (fraction != null) {
      progressBar = LinearProgressIndicator(
        value: fraction.clamp(0.0, 1.0),
        borderRadius: BorderRadius.circular(4),
        backgroundColor: cs.surfaceContainerHighest,
      );
    } else {
      progressBar = LinearProgressIndicator(
        borderRadius: BorderRadius.circular(4),
        backgroundColor: cs.surfaceContainerHighest,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  progressActivityKindIcon(activity.kind),
                  size: 20,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: styles.mdSemiboldTightSnugColored(cs.onSurface),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: styles.mdColored(cs.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 8),
                    progressBar,
                  ],
                ),
              ),
              if (activity.cancellable)
                TextButton(
                  onPressed: canCancel ? onCancel : null,
                  child: Text(l10n.cancel),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
