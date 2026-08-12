import '../../../agent_status/agent_attention_state.dart';
import '../../../agent_status/agent_status_event.dart';
import '../../../agent_status/agent_status_tool_input.dart';
import '../../../agent_status/ask_user_question.dart';
import '../../../agent_status/exit_plan_mode.dart';
import 'agent_status_normalizer_capability.dart';

/// Claude-family hook payload grammar — claude, flashskyai, and codex share
/// the same SSE event shape, so the three CLIs register this shared
/// implementation from registry shared infrastructure.
///
/// Rules mirror Orca `normalizeClaudeEvent`:
/// - AskUserQuestion / ExitPlanMode PreToolUse / PermissionRequest → waiting
/// - non-AskUserQuestion PreToolUse / PostToolUse / PostToolUseFailure /
///   UserPromptSubmit → working
/// - Stop / StopFailure → done
/// - SubagentStart / SubagentStop → null (do not mark primary done)
final class ClaudeFamilyAgentStatusNormalizer
    implements AgentStatusNormalizerCapability {
  const ClaudeFamilyAgentStatusNormalizer();

  @override
  AgentStatusEvent? normalize(Map<String, Object?> body) {
    final eventName = body['hook_event_name']?.toString();
    if (eventName == null || eventName.isEmpty) return null;

    // Why: Subagent lifecycle must not flip the primary seat to done/working.
    if (eventName == 'SubagentStart' || eventName == 'SubagentStop') {
      return null;
    }

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
      'Stop' || 'StopFailure' => build(AgentSeatAttention.done),
      _ => null,
    };
  }
}
