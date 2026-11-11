import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/ai_history_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/failed_message_record.dart';
import '../../services/chat/rewind/seat_branches.dart';
import 'session_history_rewind_host.dart';
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
    this.backgroundLabel,
    this.provisioningLabel,
    this.pendingDeliveryStatuses = const {},
    this.onRetryFailedMessage,
    this.highlightMessageId,
    this.revealRequest,
    this.visibleOwnerId,
    this.scrollAnchorKey,
    this.scrollAnchors,
    this.rewind,
    this.turnInFlight = false,
    this.suppressEmptyPane = false,
    this.pendingUserText = '',
    super.key,
  });

  final AiHistoryState state;
  final AiThreadRuntime runtime;
  final VoidCallback onRetry;
  final Future<void> Function() onLoadOlder;
  final SessionHistoryLiveChrome liveChrome;

  /// What the out-of-turn background work is doing, forwarded to the thread
  /// footer (see [SessionHistoryThread.backgroundLabel]).
  final String? backgroundLabel;

  /// Fixed status text while a remote environment provisions, forwarded to
  /// [SessionHistoryThread.provisioningLabel].
  final String? provisioningLabel;
  final Map<String, FailedMessageStatus> pendingDeliveryStatuses;

  /// Actions for a persisted failed optimistic bubble.
  final ValueChanged<String>? onRetryFailedMessage;

  /// Message id whose bubble gets a highlight ring (chat find current match).
  final String? highlightMessageId;

  /// Carries the reveal intent (jump + highlight) from the chat find host.
  final ChatRevealController? revealRequest;

  /// Owning user-turn id of the first viewport-visible turn.
  final ValueNotifier<String?>? visibleOwnerId;

  /// Key into [scrollAnchors] for transcript scroll-position restore across
  /// host remounts (see [SessionHistoryThread.scrollAnchorKey]).
  final String? scrollAnchorKey;

  /// Host-owned anchor map (sessionId → offset), typically
  /// `ChatCubit.sessionScrollAnchors`.
  final Map<String, double>? scrollAnchors;

  final SessionHistoryRewindBinding? rewind;
  final bool turnInFlight;

  /// True while a fresh session is still launching / delivering its first turn.
  ///
  /// The seat defaults to [AiHistoryViewStatus.empty], so a brand-new seat
  /// would paint "no prior messages" for the whole connect window (ACP landing
  /// sends wait on the cubit attach). Keep the loading pane during that window
  /// — a genuine empty result is only meaningful once launch settles.
  final bool suppressEmptyPane;

  /// Transient landing first prompt, painted as a user bubble plus the
  /// [SessionHistoryLiveChrome.starting] footer until the runtime owns it.
  final String pendingUserText;

  AiHistoryViewStatus get _status =>
      state.status == AiHistoryViewStatus.empty && suppressEmptyPane
      ? AiHistoryViewStatus.loading
      : state.status;

  bool get _showThread {
    // An edit rewinds and reconnects the seat, so the history status can
    // briefly flip to loading/refreshing and the runtime can publish an empty
    // list. Swapping the thread for a status pane there unmounts its State
    // (scroll position, cached bodies, optimistic bubble) and paints a
    // spinner: the visible flash. Keep it mounted for the whole edit window;
    // holdTranscript already freezes its contents until the new turn lands.
    if (rewind?.holdTranscript == true || rewind?.branchEdit.pending != null) {
      return true;
    }
    if (_status == AiHistoryViewStatus.refreshing) return true;
    // Optimistic pendings may land while status is still empty/loading, and a
    // refresh failure keeps content under an error status — any content keeps
    // the thread mounted (never the full-pane spinner or a blanked error pane).
    if (runtime.messages.isNotEmpty) return true;
    // Landing create+send: the transient bubble is the only content yet, but
    // the thread (bubble + Starting footer) is exactly the normal chat shape.
    // A history error still owns the pane — never hide it behind a bubble.
    if (pendingUserText.trim().isNotEmpty &&
        _status != AiHistoryViewStatus.error) {
      return true;
    }
    // A `ready` status with an empty runtime (dropped pending, cleared window)
    // would otherwise mount an empty scroll view: a blank pane with only the
    // composer below. Let it fall through to the status panes.
    return false;
  }

  /// Status used for the full-pane fallback when the thread has no content.
  AiHistoryViewStatus get _paneStatus => _status == AiHistoryViewStatus.ready
      ? AiHistoryViewStatus.empty
      : _status;

  @override
  Widget build(BuildContext context) {
    if (_showThread) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Every child carries a key. A softReload inserts/removes the
          // refreshing strip during a rewind reconnect; without keys Flutter
          // matches children by position and rebuilds the Expanded (and the
          // whole thread State) whenever it shifts — the visible double flash.
          if (_status == AiHistoryViewStatus.refreshing)
            const KeyedSubtree(
              key: ValueKey('session-history-refreshing-strip'),
              child: _RefreshingStrip(),
            ),
          if ((state.softReloadError?.trim() ?? '').isNotEmpty)
            const KeyedSubtree(
              key: ValueKey('session-history-soft-reload-error-strip'),
              child: _SoftReloadErrorStrip(),
            ),
          Expanded(
            key: const ValueKey('session-history-thread'),
            child: SessionHistoryThread(
              runtime: runtime,
              hasOlder: state.hasOlder,
              isLoadingOlder: state.isLoadingOlder,
              onLoadOlder: onLoadOlder,
              liveChrome: liveChrome,
              backgroundLabel: backgroundLabel,
              provisioningLabel: provisioningLabel,
              pendingDeliveryStatuses: pendingDeliveryStatuses,
              onRetryFailedMessage: onRetryFailedMessage,
              highlightMessageId: highlightMessageId,
              revealRequest: revealRequest,
              visibleOwnerId: visibleOwnerId,
              scrollAnchorKey: scrollAnchorKey,
              scrollAnchors: scrollAnchors,
              branches: rewind?.branches ?? const SeatBranches.empty(),
              onSwitchVersion: rewind?.onSwitchVersion,
              onForkFrom: rewind?.onForkFrom,
              onEditUserMessage: rewind?.onEditUserMessage,
              onPickEditAttachments: rewind?.onPickEditAttachments,
              holdTranscript: rewind?.holdTranscript ?? false,
              branchEdit: rewind?.branchEdit,
              onOptimisticLanded: rewind?.onOptimisticLanded,
              turnInFlight: turnInFlight,
              pendingUserText: pendingUserText,
            ),
          ),
        ],
      );
    }

    return switch (_paneStatus) {
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
              context.l10n.session.historyLoading,
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
          context.l10n.session.historyEmpty,
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
              context.l10n.session.historyError,
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
              child: Text(context.l10n.session.historyRetry),
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
            context.l10n.session.historyRefreshing,
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
          context.l10n.session.historySoftReloadError,
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
