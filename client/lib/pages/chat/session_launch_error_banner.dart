import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';
import 'session_launch_failure_presenter.dart';

/// Launch / process failure chrome.
///
/// [compact] is for the Terminal surface: a small top-right chip with a short
/// title + actions. Detailed [view.message] stays visible in scrollback.
/// Chat / compose use a muted recovery-style card: title + expandable details
/// + retry (and optional remap), so the raw error is not the first thing
/// users see above the input.
class SessionLaunchErrorBanner extends StatefulWidget {
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
  State<SessionLaunchErrorBanner> createState() =>
      _SessionLaunchErrorBannerState();
}

class _SessionLaunchErrorBannerState extends State<SessionLaunchErrorBanner> {
  var _reviewing = false;

  @override
  Widget build(BuildContext context) {
    if (widget.compact) return _buildCompact(context);
    return _buildComposeCard(context);
  }

  Widget _buildComposeCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final l10n = context.l10n;

    return Container(
      key: AppKeys.sessionLaunchErrorBanner,
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
              SizedBox(width: spacing.xs),
              Expanded(
                child: Text(
                  l10n.sessionFailedTitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              TextButton(
                key: AppKeys.sessionLaunchErrorReviewButton,
                onPressed: () => setState(() => _reviewing = !_reviewing),
                child: Text(
                  _reviewing
                      ? l10n.sessionLaunchErrorHideDetails
                      : l10n.sessionLaunchErrorReviewDetails,
                ),
              ),
              for (final action in widget.view.actions) ...[
                SizedBox(width: spacing.xxs),
                switch (action.kind) {
                  SessionLaunchFailureActionKind.remapDeadSsh => TextButton(
                    onPressed: widget.onRemapDeadTarget,
                    child: Text(l10n.workspaceDeadTargetRemapFromLaunch),
                  ),
                  SessionLaunchFailureActionKind.retry => TextButton.icon(
                    key: AppKeys.sessionLaunchErrorRetryButton,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(l10n.sessionRetryButton),
                    onPressed: widget.isRetrying ? null : widget.onRetry,
                  ),
                },
              ],
            ],
          ),
          if (_reviewing)
            Padding(
              padding: EdgeInsets.only(top: spacing.xs),
              child: Text(
                widget.view.message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final l10n = context.l10n;

    return DecoratedBox(
      key: AppKeys.sessionLaunchErrorBanner,
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.error.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.sessionFailedTitle,
              style: TpTextStyles.of(context).smRelaxedColored(
                cs.onErrorContainer,
              ),
            ),
            for (final action in widget.view.actions) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: switch (action.kind) {
                  SessionLaunchFailureActionKind.remapDeadSsh => TextButton(
                    onPressed: widget.onRemapDeadTarget,
                    style: _compactButtonStyle,
                    child: Text(l10n.workspaceDeadTargetRemapFromLaunch),
                  ),
                  SessionLaunchFailureActionKind.retry => TextButton(
                    key: AppKeys.sessionLaunchErrorRetryButton,
                    onPressed: widget.isRetrying ? null : widget.onRetry,
                    style: _compactButtonStyle,
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
