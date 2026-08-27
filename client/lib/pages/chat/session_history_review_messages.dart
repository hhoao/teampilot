import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/ai_history_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/failed_message_record.dart';
import 'chat_reveal_controller.dart';
import 'session_history_live_chrome.dart';
import 'session_history_thread.dart';

/// Finder key for the soft-reload non-blocking error strip.
const Key kSessionHistorySoftReloadErrorKey = ValueKey(
  'session-history-soft-reload-error',
);

/// Status switch for History review: loading / empty / error / thread.
///
/// Empty with runtime tip messages (optimistic pendings) uses the thread path.
/// Soft-reload failures stay on the thread with a slim non-blocking strip.
class SessionHistoryReviewMessages extends StatelessWidget {
  const SessionHistoryReviewMessages({
    required this.state,
    required this.runtime,
    required this.onRetry,
    required this.onLoadOlder,
    this.liveChrome = SessionHistoryLiveChrome.none,
    this.pendingDeliveryStatuses = const {},
    this.onRetryFailedMessage,
    this.highlightMessageId,
    this.revealRequest,
    super.key,
  });

  final AiHistoryState state;
  final AiThreadRuntime runtime;
  final VoidCallback onRetry;
  final VoidCallback onLoadOlder;
  final SessionHistoryLiveChrome liveChrome;
  final Map<String, FailedMessageStatus> pendingDeliveryStatuses;

  /// Actions for a persisted failed optimistic bubble.
  final ValueChanged<String>? onRetryFailedMessage;

  /// Message id whose bubble gets a highlight ring (chat find current match).
  final String? highlightMessageId;

  /// Carries the reveal intent (jump + highlight) from the chat find host.
  final ChatRevealController? revealRequest;

  bool get _showThread {
    if (state.status == AiHistoryViewStatus.ready) return true;
    if (state.status == AiHistoryViewStatus.refreshing) return true;
    // Optimistic pendings may land while status is still empty/loading, and a
    // refresh failure keeps content under an error status — any content keeps
    // the thread mounted (never the full-pane spinner or a blanked error pane).
    if (runtime.messages.isNotEmpty) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_showThread) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.status == AiHistoryViewStatus.refreshing)
            const _RefreshingStrip(),
          if ((state.softReloadError?.trim() ?? '').isNotEmpty)
            const _SoftReloadErrorStrip(),
          Expanded(
            child: SessionHistoryThread(
              runtime: runtime,
              hasOlder: state.hasOlder,
              isLoadingOlder: state.isLoadingOlder,
              onLoadOlder: onLoadOlder,
              liveChrome: liveChrome,
              pendingDeliveryStatuses: pendingDeliveryStatuses,
              onRetryFailedMessage: onRetryFailedMessage,
              highlightMessageId: highlightMessageId,
              revealRequest: revealRequest,
            ),
          ),
        ],
      );
    }

    return switch (state.status) {
      // Unreachable (refreshing always shows the thread via _showThread), but
      // required for exhaustiveness.
      AiHistoryViewStatus.refreshing => const SizedBox.shrink(),
      AiHistoryViewStatus.loading => _HistoryStatusPane(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(height: context.tpSpacing.md),
            Text(
              context.l10n.sessionHistoryLoading,
              style: TpTextStyles.of(
                context,
              ).mdColored(Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      AiHistoryViewStatus.empty => _HistoryStatusPane(
        icon: Icons.chat_bubble_outline_rounded,
        child: Text(
          context.l10n.sessionHistoryEmpty,
          style: TpTextStyles.of(
            context,
          ).mdColored(Theme.of(context).colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ),
      AiHistoryViewStatus.error => _HistoryStatusPane(
        icon: Icons.error_outline_rounded,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.sessionHistoryError,
              style: TpTextStyles.of(
                context,
              ).mdColored(Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
            if ((state.errorMessage?.trim() ?? '').isNotEmpty) ...[
              SizedBox(height: context.tpSpacing.sm),
              Text(
                state.errorMessage!.trim(),
                style: TpTextStyles.of(
                  context,
                ).smColored(Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            SizedBox(height: context.tpSpacing.md),
            TextButton(
              onPressed: onRetry,
              child: Text(context.l10n.sessionHistoryRetry),
            ),
          ],
        ),
      ),
      AiHistoryViewStatus.ready => const SizedBox.shrink(),
    };
  }
}

/// Slim non-blocking strip shown while a cached transcript is refreshing.
class _RefreshingStrip extends StatelessWidget {
  const _RefreshingStrip();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
      padding: EdgeInsets.symmetric(
        horizontal: context.tpSpacing.md,
        vertical: context.tpSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: context.tpSpacing.sm),
          Text(
            context.l10n.sessionHistoryRefreshing,
            style: TpTextStyles.of(context).smColored(cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SoftReloadErrorStrip extends StatelessWidget {
  const _SoftReloadErrorStrip();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.errorContainer.withValues(alpha: 0.55),
      child: Padding(
        key: kSessionHistorySoftReloadErrorKey,
        padding: EdgeInsets.symmetric(
          horizontal: context.tpSpacing.md,
          vertical: context.tpSpacing.sm,
        ),
        child: Text(
          context.l10n.sessionHistorySoftReloadError,
          textAlign: TextAlign.center,
          style: TpTextStyles.of(context).smColored(cs.onErrorContainer),
        ),
      ),
    );
  }
}

class _HistoryStatusPane extends StatelessWidget {
  const _HistoryStatusPane({this.icon, required this.child});

  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.tpSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(
                icon,
                size: 32,
                color: cs.onSurfaceVariant.withValues(alpha: 0.55),
              ),
            SizedBox(height: context.tpSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}
