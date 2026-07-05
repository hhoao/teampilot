import '../team_bus/team_bus.dart';

/// When to abandon stale full-screen PTY automation retries (doorbell / inject).
abstract final class PtyAutomationDeliveryGuard {
  PtyAutomationDeliveryGuard._();

  /// True when a queued paste/CR retry no longer matches bus obligations.
  ///
  /// Parked workers consume mail via MCP `wait_for_message` — PTY nudges would
  /// corrupt presence and the working indicator. Cleared inboxes with no pending
  /// doorbell/task notice mean the worker already handled the mail another way.
  static bool shouldSkipRetry({
    required TeamBus? bus,
    required String memberId,
  }) {
    if (bus == null) return false;
    if (bus.isWaitingForMessage(memberId)) return true;
    return bus.pendingDoorbellNoticeFor(memberId) == null;
  }
}
