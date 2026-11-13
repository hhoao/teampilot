import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/chat/rewind/edit/edit_operation.dart';

/// Phase line under the bubble of a message being edited and resent.
///
/// Purely informational: the only action is Retry after a failure or a stop.
/// Cancelling a running edit stays on the compose Stop button.
class EditOperationStatus extends StatelessWidget {
  const EditOperationStatus({
    required this.operation,
    this.onRetry,
    super.key,
  });

  final EditOperation operation;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final retryable = operation.phase.allowsRetry;
    final style = TpTextStyles.of(
      context,
    ).smColored(retryable ? scheme.error : scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(top: 2, right: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (operation.phase.isActive) ...[
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              _label(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (retryable && onRetry != null)
            TextButton(
              key: const ValueKey('chat-edit-retry'),
              onPressed: onRetry,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
              ),
              child: Text(context.l10n.edit.retry),
            ),
        ],
      ),
    );
  }

  String _label(BuildContext context) => switch (operation.phase) {
    EditPhase.queued || EditPhase.restoring => context.l10n.edit.statusRewinding,
    EditPhase.relaunching => context.l10n.edit.statusReconnecting,
    EditPhase.delivering ||
    EditPhase.awaitingReplay => context.l10n.edit.statusSending,
    EditPhase.cancelled => context.l10n.edit.statusStopped,
    EditPhase.failed => context.l10n.edit.statusFailed,
    EditPhase.confirmed => '',
  };
}
