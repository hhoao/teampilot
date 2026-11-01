import '../../../../models/app_session.dart';
import '../../session/chat_tab.dart';

/// Outcome of sending one prompt to one runtime seat.
enum SeatPromptDeliveryResult {
  /// Handed to the seat's runtime (ACP cubit queued or PTY submit issued).
  delivered,

  /// The seat is ACP but no runtime cubit was attached, so nothing was sent.
  runtimeUnavailable,

  /// The ACP runtime refused the prompt (turn in flight, session ended).
  rejected,

  /// The PTY submit seam did not confirm the write.
  ptyUnconfirmed,
}

/// Sends one prompt into an ACP cubit. False means the runtime refused it.
typedef AcpPromptSend = bool Function(String text);

/// Existing PTY submit seam. A non-empty delivery id means "submitted".
typedef SeatPtySubmit =
    Future<String?> Function(String sessionId, String memberId, String message);

/// True when this seat runs over ACP and has no PTY composer.
bool seatUsesAcp(AppSession session, String memberId) =>
    isAcpChatSession(session) || isAcpChatSeat(session, memberId);

/// Single policy point for "does this prompt go to ACP or the PTY seam".
///
/// ACP seats never spawn a shell: falling through to [ptySubmit] would fail
/// with `terminal_surface_unavailable`, so a missing runtime is its own result.
Future<SeatPromptDeliveryResult> deliverSeatPrompt({
  required AppSession session,
  required String memberId,
  required String message,
  required AcpPromptSend? acpSend,
  required SeatPtySubmit ptySubmit,
}) async {
  if (seatUsesAcp(session, memberId)) {
    final send = acpSend;
    if (send == null) return SeatPromptDeliveryResult.runtimeUnavailable;
    return send(message)
        ? SeatPromptDeliveryResult.delivered
        : SeatPromptDeliveryResult.rejected;
  }
  final deliveryId = await ptySubmit(session.sessionId, memberId, message);
  return deliveryId != null && deliveryId.trim().isNotEmpty
      ? SeatPromptDeliveryResult.delivered
      : SeatPromptDeliveryResult.ptyUnconfirmed;
}
