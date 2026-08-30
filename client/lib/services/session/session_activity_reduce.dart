import '../../models/session_activity.dart';

bool _isTerminalDisposition(SessionTurnDisposition disposition) =>
    disposition == SessionTurnDisposition.completed ||
    disposition == SessionTurnDisposition.cancelled ||
    disposition == SessionTurnDisposition.failed;

SessionTurnDisposition _disposition({
  required SessionActivity previous,
  required bool hadTurn,
  SessionTurnDisposition? forced,
}) {
  if (forced != null) return forced;
  if (_isTerminalDisposition(previous.disposition)) {
    return previous.disposition;
  }
  if (hadTurn && (previous.isInTurn || previous.isAttention)) {
    return SessionTurnDisposition.completed;
  }
  if (previous.isDelivering && !previous.hadTurn) {
    return SessionTurnDisposition.failed;
  }
  return SessionTurnDisposition.none;
}

SessionActivity reduceSessionActivity({
  required SessionActivity previous,
  required Set<SessionBusyReason> reasons,
  SessionTurnDisposition? forced,
}) {
  final hadTurn =
      previous.hadTurn ||
      reasons.contains(SessionBusyReason.inTurn) ||
      reasons.contains(SessionBusyReason.attention);
  if (reasons.isNotEmpty) {
    return SessionActivity(reasons: reasons, hadTurn: hadTurn);
  }
  return SessionActivity(
    reasons: const {},
    hadTurn: hadTurn,
    disposition: _disposition(
      previous: previous,
      hadTurn: hadTurn,
      forced: forced,
    ),
  );
}
