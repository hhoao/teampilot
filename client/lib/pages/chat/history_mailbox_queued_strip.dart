import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/terminal/pending_user_message.dart';

/// Finder key for the History mailbox Queued strip.
const Key kSessionHistoryMailboxQueuedStripKey = ValueKey(
  'session-history-mailbox-queued-strip',
);

/// Compose-adjacent list of TeamBus user mails waiting to be consumed.
///
/// Mirrors Terminal [ParkedSendOverlay] lifecycle: poll [isUnread], drop when
/// the member reads the mail. Dismiss hides the UI row only; consumption still
/// fires [onConsumed] so the host can promote the timeline bubble.
class HistoryMailboxQueuedStrip extends StatefulWidget {
  const HistoryMailboxQueuedStrip({
    required this.submissions,
    required this.isUnread,
    this.onConsumed,
    this.clearToken = 0,
    this.pollInterval = const Duration(seconds: 1),
    super.key,
  });

  final Stream<PendingUserMessage> submissions;
  final bool Function(String id) isUnread;

  /// Called when the member consumed the mail (visible or UI-dismissed row).
  final void Function(PendingUserMessage message)? onConsumed;

  /// Bumped by the host on seat/session change to drop in-flight Queued rows
  /// without treating them as consumed.
  final int clearToken;
  final Duration pollInterval;

  @override
  State<HistoryMailboxQueuedStrip> createState() =>
      _HistoryMailboxQueuedStripState();
}

class _HistoryMailboxQueuedStripState extends State<HistoryMailboxQueuedStrip> {
  final List<PendingUserMessage> _pending = [];
  final List<PendingUserMessage> _hiddenWatching = [];
  StreamSubscription<PendingUserMessage>? _sub;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(HistoryMailboxQueuedStrip old) {
    super.didUpdateWidget(old);
    if (!identical(old.submissions, widget.submissions) ||
        old.clearToken != widget.clearToken) {
      _pending.clear();
      _hiddenWatching.clear();
      _ticker?.cancel();
      _ticker = null;
      _subscribe();
    }
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = widget.submissions.listen(_onSubmission);
  }

  void _onSubmission(PendingUserMessage msg) {
    if (_pending.any((m) => m.id == msg.id) ||
        _hiddenWatching.any((m) => m.id == msg.id)) {
      return;
    }
    setState(() => _pending.add(msg));
    _ensureTicker();
    // Consume immediately if already read — do not wait for the first poll tick.
    _prune();
  }

  void _ensureTicker() {
    _ticker ??= Timer.periodic(widget.pollInterval, (_) => _prune());
  }

  void _prune() {
    final before = _pending.length;
    final consumed = <PendingUserMessage>[];
    for (final list in [_pending, _hiddenWatching]) {
      list.removeWhere((m) {
        if (widget.isUnread(m.id)) return false;
        consumed.add(m);
        return true;
      });
    }
    for (final msg in consumed) {
      widget.onConsumed?.call(msg);
    }
    if (_pending.isEmpty && _hiddenWatching.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
    }
    if (_pending.length != before) setState(() {});
  }

  void _dismiss(PendingUserMessage msg) {
    setState(() {
      _pending.removeWhere((m) => m.id == msg.id);
      if (!_hiddenWatching.any((m) => m.id == msg.id)) {
        _hiddenWatching.add(msg);
      }
    });
    _ensureTicker();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_pending.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    final l10n = context.l10n;
    return Padding(
      key: kSessionHistoryMailboxQueuedStripKey,
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.sessionHistoryMailboxQueued(_pending.length),
            style: styles.smColored(cs.onSurfaceVariant),
          ),
          SizedBox(height: spacing.xs),
          for (final msg in _pending)
            Padding(
              padding: EdgeInsets.only(bottom: spacing.xs),
              child: Material(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.outgoing_mail,
                        size: 18,
                        color: cs.onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          msg.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: styles.mdColored(cs.onSecondaryContainer),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: l10n.sessionHistoryMailboxQueuedDismiss,
                        color: cs.onSecondaryContainer,
                        onPressed: () => _dismiss(msg),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
