import '../../../agent_status/agent_attention_state.dart';
import '../../../agent_status/agent_permission_request.dart';
import '../../../agent_status/agent_status_event.dart';
import '../../../agent_status/agent_status_tool_input.dart';
import '../../../agent_status/ask_user_question.dart';
import '../../registry/capabilities/agent_status_normalizer_capability.dart';

/// OpenCode's own hook event format (`event`, `request_id`, …).
final class OpencodeAgentStatusNormalizer
    implements AgentStatusNormalizerCapability {
  const OpencodeAgentStatusNormalizer();

  @override
  AgentStatusEvent? normalize(Map<String, Object?> body) {
    final eventName = body['event']?.toString();
    if (eventName == null || eventName.isEmpty) return null;

    final askRequestId = readPayloadString(body, const [
      'request_id',
      'id',
      'permission_id',
    ]);
    final nativeSessionId = readPayloadString(body, const [
      'session_id',
      'sessionID',
    ]);
    final message = readPayloadString(body, const ['message']);

    return switch (eventName) {
      'permission.asked' => AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: eventName,
        askRequestId: askRequestId,
        nativeSessionId: nativeSessionId,
        permissionRequest: parsePermissionRequest(body),
      ),
      'question.asked' => AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: eventName,
        askUserQuestions: parseQuestionsList(body['questions']),
        askRequestId: askRequestId,
        nativeSessionId: nativeSessionId,
      ),
      // OpenCode resolved the request itself (native TUI answer / reject):
      // seat moves back to working so the chat card clears immediately.
      'question.answered' => AgentStatusEvent(
        state: AgentSeatAttention.working,
        hookEventName: eventName,
        askRequestId: askRequestId,
        nativeSessionId: nativeSessionId,
      ),
      'permission.answered' => AgentStatusEvent(
        state: AgentSeatAttention.working,
        hookEventName: eventName,
        askRequestId: askRequestId,
        nativeSessionId: nativeSessionId,
      ),
      'question.reply_failed' => AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: eventName,
        askRequestId: askRequestId,
        message: message,
        // Restore only when we can correlate back to the pending ask.
        restoreAskWaiting: askRequestId != null,
      ),
      // Plugin forwards the user's submitted message text so the app can ACK
      // the PTY delivery (mirror of Claude UserPromptSubmit).
      'userMessageSubmitted' => AgentStatusEvent(
        state: AgentSeatAttention.working,
        hookEventName: eventName,
        prompt: readPayloadString(body, const ['prompt']),
      ),
      'session.idle' => AgentStatusEvent(
        state: AgentSeatAttention.done,
        hookEventName: eventName,
      ),
      _ => null,
    };
  }
}
