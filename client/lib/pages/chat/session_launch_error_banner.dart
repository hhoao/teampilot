import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';
import 'session_launch_failure_presenter.dart';

/// Launch / process failure chrome.
///
/// [compact] is for the Terminal surface: a small top-right chip with a short
/// title + actions. Detailed [view.message] stays visible in scrollback.
/// Chat / compose keep the full-width detailed banner (`compact: false`).
class SessionLaunchErrorBanner extends StatelessWidget {
  const SessionLaunchErrorBanner({
    required this.view,
    this.onRetry,
    this.onRemapDeadTarget,
    this.isRetrying = false,
    this.compact = false,
    super.key,
  });

  final SessionLaunchFailureView view;
  final VoidCallback? onRetry;
  final VoidCallback? onRemapDeadTarget;
  final bool isRetrying;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final l10n = context.l10n;
    final message = compact ? l10n.sessionFailedTitle : view.message;

    return DecoratedBox(
      key: AppKeys.sessionLaunchErrorBanner,
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        border: Border.all(color: cs.error.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: compact ? spacing.xs : spacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: TpTextStyles.of(context).smRelaxedColored(
                cs.onErrorContainer,
              ),
            ),
            for (final action in view.actions) ...[
              SizedBox(height: compact ? 0 : spacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: switch (action.kind) {
                  SessionLaunchFailureActionKind.remapDeadSsh => TextButton(
                    onPressed: onRemapDeadTarget,
                    style: compact ? _compactButtonStyle : null,
                    child: Text(l10n.workspaceDeadTargetRemapFromLaunch),
                  ),
                  SessionLaunchFailureActionKind.retry => TextButton(
                    key: AppKeys.sessionLaunchErrorRetryButton,
                    onPressed: isRetrying ? null : onRetry,
                    style: compact ? _compactButtonStyle : null,
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

  static final ButtonStyle _compactButtonStyle = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );
}
