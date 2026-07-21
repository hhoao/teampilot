/// How History continue should deliver operator text for the selected seat.
enum HistoryContinueChannel {
  /// Inject at the member TUI prompt (stdin).
  pty,

  /// Enqueue on TeamBus as `from: user` mail.
  mailbox,
}

/// Result of [submitSessionHistoryReviewMessage].
final class HistoryContinueSubmitResult {
  const HistoryContinueSubmitResult({
    required this.ok,
    required this.channel,
    this.mailId,
  });

  const HistoryContinueSubmitResult.failed({
    this.channel = HistoryContinueChannel.pty,
  }) : ok = false,
       mailId = null;

  final bool ok;
  final HistoryContinueChannel channel;

  /// Non-null after a successful mailbox deliver.
  final String? mailId;

  bool get isMailbox =>
      ok && channel == HistoryContinueChannel.mailbox && mailId != null;
}

/// Mixed TeamBus seats that are waiting or mid-turn consume mailbox mail, not
/// PTY stdin. Idle seats (and sessions without a bus) stay on the PTY path.
HistoryContinueChannel resolveHistoryContinueChannel({
  required bool teamBusInstalled,
  required bool memberWaitingForMessage,
  required bool memberInTurn,
}) {
  if (!teamBusInstalled) return HistoryContinueChannel.pty;
  if (memberWaitingForMessage || memberInTurn) {
    return HistoryContinueChannel.mailbox;
  }
  return HistoryContinueChannel.pty;
}
