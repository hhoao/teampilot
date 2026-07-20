import '../../models/team_config.dart';
import 'agent_attention_state.dart';
import 'agent_status_event.dart';
import 'agent_status_tool_input.dart';

/// Maps raw CLI hook / plugin JSON to a normalized [AgentStatusEvent].
///
/// Pure: no I/O. Returns `null` for corrupt, unknown, or Cursor payloads
/// (Cursor uses the title path only).
///
/// Claude-family rules mirror Orca `normalizeClaudeEvent`:
/// - AskUserQuestion PreToolUse / PermissionRequest → waiting
/// - non-AskUserQuestion PreToolUse / PostToolUse / PostToolUseFailure /
///   UserPromptSubmit → working
/// - Stop / StopFailure → done
/// - SubagentStart / SubagentStop → null (do not mark primary done)
class AgentStatusNormalizer {
  const AgentStatusNormalizer._();

  static AgentStatusEvent? normalize({
    required CliTool cli,
    required Map<String, Object?> body,
  }) {
    return switch (cli) {
      CliTool.claude || CliTool.flashskyai || CliTool.codex =>
        _normalizeClaudeFamily(body),
      CliTool.opencode => _normalizeOpenCode(body),
      CliTool.cursor => null,
    };
  }

  static AgentStatusEvent? _normalizeClaudeFamily(Map<String, Object?> body) {
    final eventName = body['hook_event_name']?.toString();
    if (eventName == null || eventName.isEmpty) return null;

    // Why: Subagent lifecycle must not flip the primary seat to done/working.
    if (eventName == 'SubagentStart' || eventName == 'SubagentStop') {
      return null;
    }

    final toolName = _readString(body, const ['tool_name', 'toolName']);
    final askUser = isAskUserQuestionTool(toolName);
    final toolInput = deriveToolInputPreview(
      toolName,
      body['tool_input'] ?? body['input'] ?? body['arguments'],
    );
    final toolUseId = _readString(body, const ['tool_use_id', 'toolUseId']);
    final toolAgentId = _readString(body, const ['agent_id', 'agentId']);
    final toolAgentType = _readString(body, const ['agent_type', 'agentType']);

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
        );

    return switch (eventName) {
      'PermissionRequest' => build(AgentSeatAttention.waiting),
      'PreToolUse' when askUser => build(AgentSeatAttention.waiting),
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

  static AgentStatusEvent? _normalizeOpenCode(Map<String, Object?> body) {
    final eventName = body['event']?.toString();
    if (eventName == null || eventName.isEmpty) return null;

    return switch (eventName) {
      'permission.asked' || 'question.asked' => AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: eventName,
      ),
      'session.idle' => AgentStatusEvent(
        state: AgentSeatAttention.done,
        hookEventName: eventName,
      ),
      _ => null,
    };
  }

  static String? _readString(Map<String, Object?> body, List<String> keys) {
    for (final key in keys) {
      final value = body[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}

/// True for AskUserQuestion across casing variants (`AskUserQuestion`,
/// `ask_user_question`, `askUserQuestion`) — same rule as Orca.
bool isAskUserQuestionTool(String? toolName) {
  if (toolName == null || toolName.isEmpty) return false;
  final compact = toolName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
  return compact == 'askuserquestion';
}
