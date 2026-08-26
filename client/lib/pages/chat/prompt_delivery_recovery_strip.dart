import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/prompt_delivery_status_cubit.dart';
import '../../l10n/l10n_extensions.dart';

const Key kPromptDeliveryRecoveryStripKey = ValueKey(
  'prompt-delivery-recovery-strip',
);

const Key _kReviewButtonKey = ValueKey('prompt-recovery-review');
const Key _kRetryButtonKey = ValueKey('prompt-recovery-resend');

/// Mounts the compose-seat recovery surface unconditionally so its
/// post-frame [onRefresh] always runs on session open, even before any
/// recovery is visible (cold start or a `submitIssued → submittedUnknown`
/// restore). Renders [SizedBox.shrink] until a recovery becomes available.
///
/// Deliberately provider-free: it receives the durable snapshot [recovery]
/// the parent selected from [PromptDeliveryStatusCubit] plus the refresh and
/// retry callbacks, so no disk IO happens in build.
class PromptDeliveryRecoveryMount extends StatefulWidget {
  const PromptDeliveryRecoveryMount({
    required this.recovery,
    required this.onRetry,
    this.onRefresh,
    super.key,
  });

  final PromptDeliveryRecovery? recovery;
  final VoidCallback onRetry;
  final Future<void> Function()? onRefresh;

  @override
  State<PromptDeliveryRecoveryMount> createState() =>
      _PromptDeliveryRecoveryMountState();
}

class _PromptDeliveryRecoveryMountState extends State<PromptDeliveryRecoveryMount> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final refresh = widget.onRefresh;
      if (refresh == null || !mounted) return;
      unawaited(refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
    final recovery = widget.recovery;
    if (recovery == null) return const SizedBox.shrink();
    return PromptDeliveryRecoveryStrip(
      key: ValueKey('prompt-recovery-${recovery.deliveryId}'),
      recovery: recovery,
      onRetry: widget.onRetry,
      onRefresh: widget.onRefresh,
    );
  }
}

/// Compose-section recovery strip for a seat whose last submit is
/// explicitly unresolved (`submittedUnknown`).
///
/// Deliberately provider-free: it renders the durable recovery snapshot the
/// parent selected from [PromptDeliveryStatusCubit]. Retry goes through
/// [onRetry], which creates a NEW delivery id via the fenced direct path —
/// no PTY write can originate from this widget itself, and the unresolved
/// record is never resumed.
class PromptDeliveryRecoveryStrip extends StatefulWidget {
  const PromptDeliveryRecoveryStrip({
    required this.recovery,
    required this.onRetry,
    this.onRefresh,
    super.key,
  });

  final PromptDeliveryRecovery recovery;
  final VoidCallback onRetry;

  /// Reloads the seat's durable recovery state once mounted (disk IO stays
  /// out of build).
  final Future<void> Function()? onRefresh;

  @override
  State<PromptDeliveryRecoveryStrip> createState() =>
      _PromptDeliveryRecoveryStripState();
}

class _PromptDeliveryRecoveryStripState
    extends State<PromptDeliveryRecoveryStrip> {
  var _reviewing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final refresh = widget.onRefresh;
      if (refresh == null || !mounted) return;
      unawaited(refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.tpSpacing;

    return Container(
      key: kPromptDeliveryRecoveryStripKey,
      margin: EdgeInsets.only(bottom: spacing.sm),
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.help_outline_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              SizedBox(width: spacing.xs),
              Expanded(
                child: Text(
                  l10n.promptDeliveryUnknownTitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              TextButton(
                key: _kReviewButtonKey,
                onPressed: () => setState(() => _reviewing = !_reviewing),
                child: Text(
                  _reviewing
                      ? l10n.promptDeliveryHideMessage
                      : l10n.promptDeliveryReviewMessage,
                ),
              ),
              SizedBox(width: spacing.xxs),
              TextButton.icon(
                key: _kRetryButtonKey,
                icon: const Icon(Icons.send_outlined, size: 16),
                label: Text(l10n.promptDeliveryResend),
                onPressed: widget.onRetry,
              ),
            ],
          ),
          if (_reviewing)
            Padding(
              padding: EdgeInsets.only(top: spacing.xs),
              child: Text(
                widget.recovery.text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
