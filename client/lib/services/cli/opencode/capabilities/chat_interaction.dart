import '../../../agent_status/agent_attention_state.dart';
import '../../../agent_status/agent_permission_request.dart';
import '../../../agent_status/agent_status_event.dart';
import '../../../agent_status/agent_status_tool_input.dart';
import '../../../agent_status/ask_user_question.dart';
import '../../../agent_runtime/runtime_event.dart';
import '../../../../models/hook_entry.dart';
import '../../../../models/team_config.dart';
import '../../registry/capabilities/chat_interaction_capability.dart';
import '../../registry/capabilities/runtime_event_capability.dart';

/// OpenCode's own hook event format (`event`, `request_id`, …).
///
/// OpenCode answers questions through the plugin SDK (and `permission.asked`
/// allow/deny replies from the chat card); no in-chat ExitPlanMode approval
/// (keeps the "Open Terminal" fallback).
final class OpencodeChatInteraction
    implements ChatInteractionCapability, RuntimeEventCapability {
  const OpencodeChatInteraction();

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

  @override
  RuntimeEventEnvelopeDraft? normalizeRuntimeEvent(
    Map<String, Object?> raw,
    RuntimeSeatKey seat,
    DateTime occurredAt,
  ) {
    if (raw['event'] != 'userMessageSubmitted') return null;
    final prompt = readPayloadString(raw, const ['prompt']);
    if (prompt == null || prompt.isEmpty) return null;
    return RuntimeEventEnvelopeDraft.promptSubmitted(
      seat: seat,
      cli: CliTool.opencode,
      prompt: prompt,
      occurredAt: occurredAt,
      correlationStrength: promptCorrelationStrength,
    );
  }

  @override
  RuntimeCorrelationStrength get promptCorrelationStrength =>
      RuntimeCorrelationStrength.serializedPromptEpoch;

  @override
  List<HookEntry> managedHookEntries(RuntimeEventHookContext context) =>
      managedRuntimeEventHookEntries(cli: CliTool.opencode, context: context);

  @override
  bool get supportsStructuredAsk => true;

  @override
  bool get supportsInChatAnswer => true;

  @override
  bool get supportsMultiSelectInChat => true;

  @override
  bool get supportsMultiQuestionInChat => true;

  @override
  bool get supportsInChatPermissionReply => true;

  @override
  AskUserAnswerKind get answerKind => AskUserAnswerKind.pluginSdkReply;

  @override
  bool get supportsInChatApproval => false;

  @override
  ExitPlanApprovalKind get approvalKind => ExitPlanApprovalKind.none;
}
