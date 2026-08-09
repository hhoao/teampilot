/// Per-member terminal snapshot the reclaim watch feeds to [TerminalReclaimPolicy].
class TerminalReclaimSnapshot {
  const TerminalReclaimSnapshot({
    required this.sessionId,
    required this.memberId,
    required this.shellRunning,
    required this.shellConnecting,
    required this.isTeamLead,
    required this.isDisplayed,
    required this.inTurn,
    required this.hasUnread,
  });

  final String sessionId;
  final String memberId;
  final bool shellRunning;
  final bool shellConnecting;
  final bool isTeamLead;
  final bool isDisplayed;
  final bool inTurn;
  final bool hasUnread;
}

/// Pure reclaim decision. Single source of truth for the protection set:
/// lead, displayed terminal, working/in-turn, unread, or connecting/pending.
class TerminalReclaimPolicy {
  const TerminalReclaimPolicy({required this.idleAfter});

  final Duration idleAfter;

  bool isProtected(TerminalReclaimSnapshot s) =>
      !s.shellRunning ||
      s.shellConnecting ||
      s.isTeamLead ||
      s.isDisplayed ||
      s.inTurn ||
      s.hasUnread;

  /// true when the member has been idle since [idleSince] for at least
  /// [idleAfter] and no protection guard applies.
  bool shouldReclaim(
    TerminalReclaimSnapshot s,
    DateTime? idleSince,
    DateTime now,
  ) {
    if (isProtected(s)) return false;
    if (idleSince == null) return false;
    return now.difference(idleSince) >= idleAfter;
  }
}
