import '../../../agent_status/agent_attention_state.dart';
import '../../../agent_status/agent_permission_request.dart';
import '../../../agent_status/agent_status_event.dart';
import '../../../agent_status/agent_status_tool_input.dart';
import '../../../agent_status/ask_user_question.dart';
import '../../../agent_status/exit_plan_mode.dart';

/// Claude-family hook payload grammar — claude, flashskyai, and codex share
/// the same SSE event shape, so the three CLIs compose this shared
/// implementation from registry shared infrastructure.
///
/// Rules mirror Orca `normalizeClaudeEvent`:
/// - AskUserQuestion / ExitPlanMode PreToolUse / PermissionRequest → waiting
/// - non-AskUserQuestion PreToolUse / PostToolUse / PostToolUseFailure /
///   UserPromptSubmit → working
/// - Stop / StopFailure → done
/// - SubagentStart / SubagentStop → working carrying `agent_id`; the
///   attention cubit counts concurrent children so a child completion never
///   completes the parent seat while siblings still run.
final class ClaudeFamilyAgentStatusNormalizer {
  const ClaudeFamilyAgentStatusNormalizer();

  AgentStatusEvent? normalize(Map<String, Object?> body) {
    final eventName = body['hook_event_name']?.toString();
    if (eventName == null || eventName.isEmpty) return null;

    final toolName = readPayloadString(body, const ['tool_name', 'toolName']);
    final prompt = readPayloadString(body, const ['prompt']);
    final askUser = isAskUserQuestionTool(toolName);
    final exitPlan = isExitPlanModeTool(toolName);
    final rawToolInput = body['tool_input'] ?? body['input'] ?? body['arguments'];
    final toolInput = deriveToolInputPreview(toolName, rawToolInput);
    final toolUseId = readPayloadString(body, const ['tool_use_id', 'toolUseId']);
    final toolAgentId = readPayloadString(body, const ['agent_id', 'agentId']);
    final toolAgentType = readPayloadString(
      body,
      const ['agent_type', 'agentType'],
    );

    // AskUserQuestion / ExitPlanMode carry structured payloads the chat needs
    // to render (and optionally answer / confirm).
    final askUserQuestions =
        askUser ? parseAskUserQuestions(rawToolInput) : null;
    final planText = exitPlan ? parseExitPlanModeText(rawToolInput) : null;
    final planFilePath = exitPlan
        ? parseExitPlanModeFilePath(rawToolInput)
        : null;

    // AskUserQuestion PreToolUse: askRequestId mirrors tool_use_id so answer
    // correlation works the same as OpenCode request_id.
    final askRequestId = askUser ? toolUseId : null;

    // General Claude-family permission request (not AskUserQuestion /
    // ExitPlanMode, which have their own card paths).
    final permissionRequest =
        eventName == 'PermissionRequest' && !askUser && !exitPlan
            ? parseClaudePermissionRequest(
                body,
                toolName: toolName ?? '',
                toolInputPreview: toolInput,
              )
            : null;

    AgentStatusEvent build(AgentSeatAttention state, {bool explicit = false}) =>
        AgentStatusEvent(
          state: state,
          toolName: toolName,
          toolInput: toolInput,
          hookEventName: eventName,
          toolUseId: toolUseId,
          toolAgentId: toolAgentId,
          toolAgentType: toolAgentType,
          hasExplicitPrompt: explicit,
          prompt: prompt,
          askUserQuestions: askUserQuestions,
          askRequestId: askRequestId,
          planText: planText,
          planFilePath: planFilePath,
          permissionRequest: permissionRequest,
        );

    return switch (eventName) {
      'PermissionRequest' => build(AgentSeatAttention.waiting),
      'PreToolUse' when askUser || exitPlan => build(
        AgentSeatAttention.waiting,
      ),
      'PreToolUse' || 'PostToolUse' || 'PostToolUseFailure' => build(
        AgentSeatAttention.working,
      ),
      'UserPromptSubmit' => build(
        AgentSeatAttention.working,
        explicit: true,
      ),
      // Subagent lifecycle stays `working`; the cubit interprets the event
      // name and child id — a child stop must not read as parent completion.
      'SubagentStart' || 'SubagentStop' => build(AgentSeatAttention.working),
      'Stop' || 'StopFailure' => build(AgentSeatAttention.done),
      _ => null,
    };
  }
}
