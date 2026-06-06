/// Result of [TeamBus.send] — delivered to a member or dropped with a reason.
class SendOutcome {
  const SendOutcome._({
    required this.to,
    this.memberId,
    this.reason,
  });

  const SendOutcome.delivered(String memberId)
    : this._(to: memberId, memberId: memberId);

  const SendOutcome.dropped({required String reason, required String to})
    : this._(to: to, reason: reason);

  /// Original [TeamMessage.to] address passed to send.
  final String to;

  /// Resolved member id when delivered.
  final String? memberId;

  /// Drop reason when not delivered (`over-hop`, `unknown-member`, …).
  final String? reason;

  bool get delivered => memberId != null;
}
