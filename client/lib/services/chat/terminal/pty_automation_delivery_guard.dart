import '../team_bus/team_bus.dart';

/// When to abandon stale full-screen PTY automation retries (doorbell / inject).
abstract final class PtyAutomationDeliveryGuard {
  PtyAutomationDeliveryGuard._();

  /// True when a queued paste/CR retry no longer matches bus obligations.
  ///
  /// Parked workers consume mail via MCP `wait_for_message` — doorbell PTY nudges
  /// must not retry. Active agent turns keep retrying until submit succeeds.
  static bool shouldSkipRetry({
    required TeamBus? bus,
    required String memberId,
    bool memberInTurn = false,
    bool pendingAutomationRetry = false,
  }) {
    if (memberInTurn) return false;
    if (pendingAutomationRetry) return false;
    if (bus == null) return false;
    if (bus.isWaitingForMessage(memberId)) return true;
    return bus.pendingDoorbellNoticeFor(memberId) == null;
  }
}
