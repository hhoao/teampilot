import '../../models/app_session.dart';
import '../chat/launch/session/seat_prompt_delivery.dart';

/// Result of one automation prompt delivery.
class AutomationDeliveryOutcome {
  const AutomationDeliveryOutcome.delivered()
    : delivered = true,
      reason = null;

  const AutomationDeliveryOutcome.failed(this.reason) : delivered = false;

  final bool delivered;

  /// Diagnostic code stored on [AutomationRun.error]; never user-facing copy.
  final String? reason;
}

/// Resolves the ACP sender for one seat; null means "no runtime attached".
typedef AutomationAcpSendResolver = AcpPromptSend? Function();

/// Delivers one automation prompt to [memberId], activating a missing ACP
/// runtime once before giving up.
Future<AutomationDeliveryOutcome> deliverAutomationPrompt({
  required AppSession session,
  required String memberId,
  required String message,
  required AutomationAcpSendResolver acpSend,
  required Future<void> Function() activateAcp,
  required SeatPtySubmit ptySubmit,
  Duration activationTimeout = const Duration(seconds: 30),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  if (seatUsesAcp(session, memberId) && acpSend() == null) {
    await activateAcp();
    final deadline = DateTime.now().add(activationTimeout);
    while (acpSend() == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
    }
  }
  final result = await deliverSeatPrompt(
    session: session,
    memberId: memberId,
    message: message,
    acpSend: acpSend(),
    ptySubmit: ptySubmit,
  );
  return switch (result) {
    SeatPromptDeliveryResult.delivered =>
      const AutomationDeliveryOutcome.delivered(),
    SeatPromptDeliveryResult.runtimeUnavailable =>
      const AutomationDeliveryOutcome.failed('acp_runtime_unavailable'),
    SeatPromptDeliveryResult.rejected =>
      const AutomationDeliveryOutcome.failed('acp_prompt_rejected'),
    SeatPromptDeliveryResult.ptyUnconfirmed =>
      const AutomationDeliveryOutcome.failed('pty_submit_failed'),
  };
}
