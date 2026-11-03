import 'dart:async';

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

/// Prompt-acceptance readiness of the ACP runtime behind [AutomationAcpSendResolver].
enum AutomationAcpReadiness {
  /// No cubit attached yet (activation may still create one).
  missing,

  /// Cubit attached, agent handshake still in flight. `sendPrompt` would queue
  /// the prompt and silently drop it if the handshake then fails.
  launching,

  /// Cubit in [AcpChatPhase.ready] or [AcpChatPhase.idle] — prompts are sent
  /// straight to the agent.
  ready,

  /// Cubit ended (launch failure / process exit); prompts are refused.
  ended,
}

/// Reads the current [AutomationAcpReadiness] for one seat.
typedef AutomationAcpReadinessResolver = AutomationAcpReadiness Function();

/// Delivers one automation prompt to [memberId], activating a missing ACP
/// runtime once before giving up.
///
/// ACP delivery waits for a prompt-accepting phase ([AutomationAcpReadiness.ready])
/// before sending. A prompt queued behind `launching` is dropped by the cubit
/// on a failed handshake, so returning `delivered` for it would be a lie.
///
/// Failure reasons (diagnostic only):
/// - `acp_activation_failed` — [activateAcp] threw or exceeded [activationTimeout].
/// - `acp_runtime_unavailable` — no cubit attached, or the runtime never became
///   prompt-ready before [activationTimeout] elapsed.
/// - `acp_prompt_rejected` — the runtime ended, or `sendPrompt` refused the turn.
/// - `pty_submit_failed` — the PTY seam did not confirm the write.
Future<AutomationDeliveryOutcome> deliverAutomationPrompt({
  required AppSession session,
  required String memberId,
  required String message,
  required AutomationAcpSendResolver acpSend,
  required AutomationAcpReadinessResolver acpReadiness,
  required Future<void> Function() activateAcp,
  required SeatPtySubmit ptySubmit,
  Duration activationTimeout = const Duration(seconds: 30),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  if (!seatUsesAcp(session, memberId)) {
    return _outcome(
      await deliverSeatPrompt(
        session: session,
        memberId: memberId,
        message: message,
        acpSend: null,
        ptySubmit: ptySubmit,
      ),
    );
  }

  var readiness = acpReadiness();
  if (readiness == AutomationAcpReadiness.missing) {
    try {
      // A hung activation must not hold the serialized scheduler queue.
      await activateAcp().timeout(activationTimeout);
    } on Object {
      return const AutomationDeliveryOutcome.failed('acp_activation_failed');
    }
    readiness = await _awaitReadiness(
      acpReadiness,
      (current) => current != AutomationAcpReadiness.missing,
      timeout: activationTimeout,
      pollInterval: pollInterval,
    );
    if (readiness == AutomationAcpReadiness.missing) {
      return const AutomationDeliveryOutcome.failed('acp_runtime_unavailable');
    }
  }

  readiness = await _awaitReadiness(
    acpReadiness,
    (current) =>
        current == AutomationAcpReadiness.ready ||
        current == AutomationAcpReadiness.ended,
    timeout: activationTimeout,
    pollInterval: pollInterval,
  );
  if (readiness == AutomationAcpReadiness.ended) {
    return const AutomationDeliveryOutcome.failed('acp_prompt_rejected');
  }
  if (readiness != AutomationAcpReadiness.ready) {
    // Still `launching` when the cap elapsed: never queue a prompt we cannot
    // confirm.
    return const AutomationDeliveryOutcome.failed('acp_runtime_unavailable');
  }

  final send = acpSend();
  if (send == null) {
    return const AutomationDeliveryOutcome.failed('acp_runtime_unavailable');
  }
  return _outcome(
    await deliverSeatPrompt(
      session: session,
      memberId: memberId,
      message: message,
      acpSend: send,
      ptySubmit: ptySubmit,
    ),
  );
}

Future<AutomationAcpReadiness> _awaitReadiness(
  AutomationAcpReadinessResolver read,
  bool Function(AutomationAcpReadiness readiness) done, {
  required Duration timeout,
  required Duration pollInterval,
}) async {
  final deadline = DateTime.now().add(timeout);
  var readiness = read();
  while (!done(readiness) && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(pollInterval);
    readiness = read();
  }
  return readiness;
}

AutomationDeliveryOutcome _outcome(SeatPromptDeliveryResult result) =>
    switch (result) {
      SeatPromptDeliveryResult.delivered =>
        const AutomationDeliveryOutcome.delivered(),
      SeatPromptDeliveryResult.runtimeUnavailable =>
        const AutomationDeliveryOutcome.failed('acp_runtime_unavailable'),
      SeatPromptDeliveryResult.rejected =>
        const AutomationDeliveryOutcome.failed('acp_prompt_rejected'),
      SeatPromptDeliveryResult.ptyUnconfirmed =>
        const AutomationDeliveryOutcome.failed('pty_submit_failed'),
    };
