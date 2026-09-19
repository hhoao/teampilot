/// PTY doorbell / mailbox notify lifecycle (orthogonal to [MemberActivity]).
enum MailboxDeliveryPhase {
  /// No unread mail, or agent consumed via MCP and no notify in flight.
  none,

  /// Unread mail owed a PTY notify; inject not started or awaiting retry window.
  pending,

  /// Bus-initiated PTY doorbell inject in progress (Phase 2+; Phase 1 may skip).
  inFlight,

  /// Retry budget exhausted; unread remains — agent may still pull via MCP.
  failed,
}

/// Last PTY automation error before [MailboxDeliveryPhase.failed].
enum MailboxDeliveryError {
  crStuck,
  pasteNotFound,
  aborted,
}
