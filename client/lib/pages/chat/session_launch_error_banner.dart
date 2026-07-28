import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';
import 'session_launch_failure_presenter.dart';

class SessionLaunchErrorBanner extends StatelessWidget {
  const SessionLaunchErrorBanner({
    required this.view,
    this.onRetry,
    this.onRemapDeadTarget,
    this.isRetrying = false,
    super.key,
  });

  final SessionLaunchFailureView view;
  final VoidCallback? onRetry;
  final VoidCallback? onRemapDeadTarget;
  final bool isRetrying;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final l10n = context.l10n;

    return DecoratedBox(
      key: AppKeys.sessionLaunchErrorBanner,
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              view.message,
              style: TpTextStyles.of(context).smRelaxedColored(
                cs.onErrorContainer,
              ),
            ),
            for (final action in view.actions) ...[
              SizedBox(height: spacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: switch (action.kind) {
                  SessionLaunchFailureActionKind.remapDeadSsh => TextButton(
                    onPressed: onRemapDeadTarget,
                    child: Text(l10n.workspaceDeadTargetRemapFromLaunch),
                  ),
                  SessionLaunchFailureActionKind.retry => TextButton(
                    key: AppKeys.sessionLaunchErrorRetryButton,
                    onPressed: isRetrying ? null : onRetry,
                    child: Text(l10n.sessionRetryButton),
                  ),
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
