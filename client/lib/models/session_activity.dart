import 'package:equatable/equatable.dart';

enum SessionBusyReason { delivering, inTurn, attention }

enum SessionTurnDisposition { none, completed, cancelled, failed }

class SessionActivity extends Equatable {
  const SessionActivity({
    this.reasons = const {},
    this.hadTurn = false,
    this.disposition = SessionTurnDisposition.none,
  });

  final Set<SessionBusyReason> reasons;
  final bool hadTurn;
  final SessionTurnDisposition disposition;

  bool get isBusy => reasons.isNotEmpty;
  bool get isDelivering => reasons.contains(SessionBusyReason.delivering);
  bool get isInTurn => reasons.contains(SessionBusyReason.inTurn);
  bool get isAttention => reasons.contains(SessionBusyReason.attention);
  bool get isReadyToChat =>
      !isBusy &&
      hadTurn &&
      disposition == SessionTurnDisposition.completed;

  SessionActivity copyWith({
    Set<SessionBusyReason>? reasons,
    bool? hadTurn,
    SessionTurnDisposition? disposition,
  }) => SessionActivity(
    reasons: reasons ?? this.reasons,
    hadTurn: hadTurn ?? this.hadTurn,
    disposition: disposition ?? this.disposition,
  );

  @override
  List<Object?> get props => [reasons, hadTurn, disposition];
}
