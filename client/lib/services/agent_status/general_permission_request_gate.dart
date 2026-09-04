import 'seat_hold_gate.dart';

/// Reply for a held Claude-family general `PermissionRequest` hook — the
/// official `decision` object (see Claude Code hooks reference:
/// "PermissionRequest decision control").
///
/// `updatedPermissions` echoes a `permission_suggestions` entry for
/// "always allow" persistence; a hook allow never overrides a matching deny
/// rule (official semantics).
final class GeneralPermissionRequestReply {
  const GeneralPermissionRequestReply.allow({
    this.updatedPermissions = const [],
  }) : deny = false,
       message = null;

  const GeneralPermissionRequestReply.deny(this.message) : deny = true,
       updatedPermissions = const [];

  final bool deny;

  /// Deny reason shown to Claude (allow it to adapt).
  final String? message;

  /// Echoed `permission_suggestions` entries (allow + always only).
  final List<Map<String, Object?>> updatedPermissions;

  Map<String, Object?> toHookResponse() => {
    'hookSpecificOutput': {
      'hookEventName': 'PermissionRequest',
      'decision': {
        'behavior': deny ? 'deny' : 'allow',
        if (!deny && updatedPermissions.isNotEmpty)
          'updatedPermissions': updatedPermissions,
        if (deny && message != null) 'message': message,
      },
    },
  };
}

/// Holds open Claude-family general `PermissionRequest` HTTP hooks until the
/// chat card answers. Seat-keyed single slot: Claude blocks the turn while a
/// permission decision is pending, so one seat has at most one live request.
///
/// Parallel to `ExitPlanPermissionRequestGate`; releaseHold answers `{}` so
/// the native TUI prompt takes over (card "answer in terminal").
final class GeneralPermissionRequestGate {
  GeneralPermissionRequestGate()
    : _hold = SeatHoldGate<GeneralPermissionRequestReply>(
        staleReply:
            () => const GeneralPermissionRequestReply.deny(
              'Replaced by a newer permission request',
            ),
      );

  final SeatHoldGate<GeneralPermissionRequestReply> _hold;

  Future<GeneralPermissionRequestReply?> wait({
    required String sessionId,
    required String memberId,
    Duration timeout = const Duration(hours: 24),
  }) => _hold.wait(sessionId: sessionId, memberId: memberId, timeout: timeout);

  bool complete({
    required String sessionId,
    required String memberId,
    required GeneralPermissionRequestReply reply,
  }) => _hold.complete(
    sessionId: sessionId,
    memberId: memberId,
    reply: reply,
  );

  bool releaseHold({required String sessionId, required String memberId}) =>
      _hold.releaseHold(sessionId: sessionId, memberId: memberId);

  bool hasWaiter({required String sessionId, required String memberId}) =>
      _hold.hasWaiter(sessionId: sessionId, memberId: memberId);

  void clearSeat({required String sessionId, required String memberId}) =>
      _hold.clearSeat(sessionId: sessionId, memberId: memberId);

  void clearSession(String sessionId) => _hold.clearSession(sessionId);
}
