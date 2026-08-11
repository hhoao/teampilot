import '../../../agent_status/agent_attention_state.dart';
import '../../../agent_status/agent_status_event.dart';
import '../../../agent_status/agent_status_tool_input.dart';
import '../../registry/capabilities/agent_status_normalizer_capability.dart';

/// Cursor hook payloads mirror Claude Code's keys (`hook_event_name`,
/// `tool_name`, `tool_use_id`); the event names differ (camelCase), so map
/// them to tool-lifecycle attention. Waiting stays on the OSC-title path
/// (`detectCursorTitleAttention`) — cursor asks questions as plain text, not
/// a structured tool.
final class CursorAgentStatusNormalizer
    implements AgentStatusNormalizerCapability {
  const CursorAgentStatusNormalizer();

  @override
  AgentStatusEvent? normalize(Map<String, Object?> body) {
    final eventName = body['hook_event_name']?.toString();
    if (eventName == null || eventName.isEmpty) return null;
    final toolName = readPayloadString(body, const ['tool_name', 'toolName']);
    final toolUseId = readPayloadString(body, const [
      'tool_use_id',
      'toolUseId',
    ]);
    AgentStatusEvent build(AgentSeatAttention state) => AgentStatusEvent(
      state: state,
      toolName: toolName,
      hookEventName: eventName,
      toolUseId: toolUseId,
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
}
