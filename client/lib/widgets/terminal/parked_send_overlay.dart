import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/terminal/pending_user_message.dart';

/// Banner overlay that confirms lines sent to the team bus while a member is
/// parked on `wait_for_message`. A banner persists until [isUnread] reports the
/// recipient consumed it (or the user dismisses it manually). Self-contained so
/// it can be unit-tested without a real terminal engine.
class ParkedSendOverlay extends StatefulWidget {
  const ParkedSendOverlay({
    required this.submissions,
    required this.isUnread,
    this.pollInterval = const Duration(seconds: 1),
    super.key,
  });

  final Stream<PendingUserMessage> submissions;
  final bool Function(String id) isUnread;
  final Duration pollInterval;

  @override
  State<ParkedSendOverlay> createState() => _ParkedSendOverlayState();
}

class _ParkedSendOverlayState extends State<ParkedSendOverlay> {
  final List<PendingUserMessage> _pending = [];
  StreamSubscription<PendingUserMessage>? _sub;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(ParkedSendOverlay old) {
    super.didUpdateWidget(old);
    if (!identical(old.submissions, widget.submissions)) {
      _pending.clear();
      _subscribe();
    }
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = widget.submissions.listen(_onSubmission);
  }

  void _onSubmission(PendingUserMessage msg) {
    if (_pending.any((m) => m.id == msg.id)) return;
    setState(() => _pending.add(msg));
    _ensureTicker();
  }

  void _ensureTicker() {
    _ticker ??= Timer.periodic(widget.pollInterval, (_) => _prune());
  }

  void _prune() {
    final before = _pending.length;
    _pending.removeWhere((m) => !widget.isUnread(m.id));
    if (_pending.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
    }
    if (_pending.length != before) setState(() {});
  }

  void _dismiss(PendingUserMessage msg) {
    setState(() => _pending.removeWhere((m) => m.id == msg.id));
    if (_pending.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
    }
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
    final l10n = context.l10n;
    return Positioned(
      left: 8,
      right: 8,
      bottom: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final msg in _pending)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Material(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: [
                      Icon(Icons.outgoing_mail,
                          size: 18, color: cs.onSecondaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.terminalParkedSendPending(msg.content),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSecondaryContainer),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, size: 16),
                        tooltip: l10n.terminalParkedSendDismiss,
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
