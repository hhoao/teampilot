import '../../../cubits/session/acp/acp_chat_runtime_cubit.dart';
import '../../../models/app_session.dart';
import '../../../services/chat/launch/session/member_input_ready_wait.dart';
import '../../../services/chat/session/chat_tab.dart';

typedef LandingPtySubmit =
    Future<String?> Function(String sessionId, String memberId, String message);

/// Whether landing should write a PTY optimistic bubble before delivery.
///
/// ACP [AcpChatRuntimeCubit.sendPrompt] already appends the user message.
/// A `pending:<uuid>` overlay uses a different id, so seat adopt would paint
/// two user bubbles for the same text.
bool shouldPersistLandingHistoryPending({
  required bool switchToTerminal,
  required AppSession session,
}) => !switchToTerminal && !isAcpChatSession(session);

/// Landing prompt for a personal ACP session goes to
/// [AcpChatRuntimeCubit.sendPrompt], never PTY `issueSubmit` — those sessions
/// never spawn a shell, so prompt-delivery would throw
/// `Cannot transition failed to submitIssued`.
Future<bool> deliverWorkspaceLandingPrompt({
  required AppSession session,
  required AcpChatRuntimeCubit? acpRuntime,
  required String memberId,
  required String message,
  required LandingPtySubmit ptySubmit,
}) async {
  if (isAcpChatSession(session)) {
    if (acpRuntime == null) return false;
    return acpRuntime.sendPrompt(message);
  }
  final deliveryId = await ptySubmit(session.sessionId, memberId, message);
  return deliveryId != null && deliveryId.trim().isNotEmpty;
}

/// Result of overlapping ACP connect with an early [sendPrompt].
class AcpLandingQueueResult {
  const AcpLandingQueueResult({required this.connected, required this.queued});

  /// Whether the session connect/handshake finished successfully.
  final bool connected;

  /// Whether the landing text was accepted by [AcpChatRuntimeCubit.sendPrompt].
  final bool queued;
}

/// Queues the landing prompt as soon as the ACP cubit is attached.
///
/// The cubit is assigned before handshake finishes. Waiting for [connect]
/// first lets a CLI probe `none` paint as the first chat row, then replace
/// it with the user bubble after a blank handshake.
Future<AcpLandingQueueResult> queueAcpLandingPromptDuringConnect({
  required Future<bool> connect,
  required AcpChatRuntimeCubit? Function() lookup,
  required bool Function() cancelled,
  required String message,
  Duration cap = defaultMemberInputReadyCap,
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  final runtime = await waitForLandingAcpRuntime(
    lookup: lookup,
    cancelled: cancelled,
    cap: cap,
    pollInterval: pollInterval,
  );
  var queued = false;
  if (runtime != null && !cancelled()) {
    queued = runtime.sendPrompt(message);
  }
  final connected = await connect;
  if (connected && !queued && !cancelled()) {
    final lateRuntime = lookup();
    if (lateRuntime != null) {
      queued = lateRuntime.sendPrompt(message);
    }
  }
  return AcpLandingQueueResult(connected: connected, queued: queued);
}

/// Waits until the tab's ACP cubit is attached (or [cap] / cancel).
Future<AcpChatRuntimeCubit?> waitForLandingAcpRuntime({
  required AcpChatRuntimeCubit? Function() lookup,
  required bool Function() cancelled,
  Duration cap = defaultMemberInputReadyCap,
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(cap);
  while (true) {
    if (cancelled()) return null;
    final cubit = lookup();
    if (cubit != null) return cubit;
    if (!DateTime.now().isBefore(deadline)) return lookup();
    await Future<void>.delayed(pollInterval);
  }
}
