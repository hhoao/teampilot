import '../../models/team_config.dart';
import 'agent_attention_state.dart';
import 'agent_status_event.dart';

/// Maps raw CLI hook / plugin JSON to a normalized [AgentStatusEvent].
///
/// Pure: no I/O. Returns `null` for corrupt, unknown, or Cursor payloads
/// (Cursor uses the title path only).
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

    final toolName = body['tool_name']?.toString();

    return switch (eventName) {
      'PermissionRequest' => AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          toolName: toolName,
        ),
      'PreToolUse' when toolName == 'AskUserQuestion' => AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          toolName: toolName,
        ),
      // v1 sticky: any PostToolUse / Stop / UserPromptSubmit clears wait.
      'PostToolUse' || 'UserPromptSubmit' => AgentStatusEvent(
          state: AgentSeatAttention.working,
          toolName: toolName,
        ),
      'Stop' => AgentStatusEvent(
          state: AgentSeatAttention.done,
          toolName: toolName,
        ),
      _ => null,
    };
  }

  static AgentStatusEvent? _normalizeOpenCode(Map<String, Object?> body) {
    final eventName = body['event']?.toString();
    if (eventName == null || eventName.isEmpty) return null;

    return switch (eventName) {
      'permission.asked' || 'question.asked' => const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
        ),
      'session.idle' => const AgentStatusEvent(state: AgentSeatAttention.done),
      _ => null,
    };
  }
}
