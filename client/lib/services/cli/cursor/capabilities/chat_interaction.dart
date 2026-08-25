import '../../../agent_status/agent_attention_state.dart';
import '../../../agent_status/agent_status_event.dart';
import '../../../agent_status/agent_status_tool_input.dart';
import '../../../agent_runtime/runtime_event.dart';
import '../../../../models/hook_entry.dart';
import '../../../../models/team_config.dart';
import '../../registry/capabilities/chat_interaction_capability.dart';
import '../../registry/capabilities/runtime_event_capability.dart';

/// Cursor hook payloads mirror Claude Code's keys (`hook_event_name`,
/// `tool_name`, `tool_use_id`); the event names differ (camelCase), so map
/// them to tool-lifecycle attention. Waiting stays on the OSC-title path
/// (`detectCursorTitleAttention`) — cursor asks questions as plain text, not
/// a structured tool.
///
/// Cursor has no structured question payload (asks as plain terminal text)
/// and no in-chat ExitPlanMode approval (keeps the "Open Terminal" fallback).
final class CursorChatInteraction
    implements ChatInteractionCapability, RuntimeEventCapability {
  const CursorChatInteraction();

  @override
  AgentStatusEvent? normalize(Map<String, Object?> body) {
    final eventName = body['hook_event_name']?.toString();
    if (eventName == null || eventName.isEmpty) return null;
    final toolName = readPayloadString(body, const ['tool_name', 'toolName']);
    final prompt = readPayloadString(body, const ['prompt']);
    final toolUseId = readPayloadString(body, const [
      'tool_use_id',
      'toolUseId',
    ]);
    AgentStatusEvent build(AgentSeatAttention state) => AgentStatusEvent(
      state: state,
      toolName: toolName,
      hookEventName: eventName,
      toolUseId: toolUseId,
      prompt: prompt,
    );
    return switch (eventName) {
      'preToolUse' ||
      'postToolUse' ||
      'postToolUseFailure' ||
      'beforeSubmitPrompt' ||
      'afterAgentResponse' ||
      'beforeShellExecution' ||
      'beforeMCPExecution' => build(AgentSeatAttention.working),
      'stop' => build(AgentSeatAttention.done),
      _ => null,
    };
  }

  @override
  RuntimeEventEnvelopeDraft? normalizeRuntimeEvent(
    Map<String, Object?> raw,
    RuntimeSeatKey seat,
    DateTime occurredAt,
  ) {
    if (raw['hook_event_name'] != 'beforeSubmitPrompt') return null;
    final prompt = readPayloadString(raw, const ['prompt']);
    if (prompt == null || prompt.isEmpty) return null;
    return RuntimeEventEnvelopeDraft.promptSubmitted(
      seat: seat,
      cli: CliTool.cursor,
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
      managedRuntimeEventHookEntries(cli: CliTool.cursor, context: context);

  @override
  bool get supportsStructuredAsk => false;

  @override
  bool get supportsInChatAnswer => false;

  @override
  bool get supportsMultiSelectInChat => false;

  @override
  bool get supportsMultiQuestionInChat => false;

  @override
  bool get supportsInChatPermissionReply => false;

  @override
  AskUserAnswerKind get answerKind => AskUserAnswerKind.none;

  @override
  bool get supportsInChatApproval => false;

  @override
  ExitPlanApprovalKind get approvalKind => ExitPlanApprovalKind.none;
}
