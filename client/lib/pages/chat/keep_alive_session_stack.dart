import 'package:flutter/widgets.dart';
import 'package:shared_ui/shared_ui.dart';

/// Constant center container for open chat sessions.
///
/// Each [hosts] entry stays mounted across switches; only the host whose id
/// matches [activeSessionId] is visible and ticking. Switching changes only the
/// index — no unmount, no remount, no history reload. Mirrors the terminal's
/// `TpDeferredForegroundMount` keep-alive approach so a session's scrollback,
/// compose draft, and transcript survive a tab round-trip.
///
/// Inactive hosts are wrapped in [TpKeepAliveLayer] — unlike [Offstage] they
/// are not laid out every frame, so opening many sessions does not multiply
/// the layout cost of the active transcript.
class KeepAliveSessionStack extends StatelessWidget {
  const KeepAliveSessionStack({
    required this.sessionIds,
    required this.activeSessionId,
    required this.hosts,
    super.key,
  });

  /// Parallel to [hosts]: `hosts[i]` renders `sessionIds[i]`.
  final List<String> sessionIds;
  final String? activeSessionId;
  final List<Widget> hosts;

  @override
  Widget build(BuildContext context) {
    assert(sessionIds.length == hosts.length,
        'sessionIds and hosts must be parallel lists');
    final activeIndex = activeSessionId == null
        ? -1
        : sessionIds.indexOf(activeSessionId!);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < hosts.length; i++)
          TpKeepAliveLayer(
            active: i == activeIndex,
            child: TickerMode(
              enabled: i == activeIndex,
              child: hosts[i],
            ),
          ),
      ],
    );
  }
}
