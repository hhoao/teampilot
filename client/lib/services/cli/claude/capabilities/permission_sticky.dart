import '../../../agent_status/agent_attention_state.dart';
import '../../../agent_status/agent_status_event.dart';

/// Orca `shouldKeepClaudePermissionVisible`: keep sticky waiting unless the
/// next hook resumes the approved tool or carries an explicit user prompt.
///
/// Synthetic events (no [AgentStatusEvent.hookEventName]) bypass sticky so
/// operator-turn latch / OSC / idle backups can clear waiting.
bool shouldKeepClaudePermissionVisible(
  AgentStatusEvent? previous,
  AgentStatusEvent next,
) {
  if (previous == null) return false;
  if (previous.state != AgentSeatAttention.waiting) return false;
  if (next.state != AgentSeatAttention.working) return false;
  final prevHook = previous.hookEventName?.trim() ?? '';
  final nextHook = next.hookEventName?.trim() ?? '';
  if (prevHook.isEmpty || nextHook.isEmpty) return false;
  if (next.hasExplicitPrompt) return false;
  if (isClaudePermissionResumingApprovedTool(previous, next)) return false;
  // Why: Claude can run subagents concurrently in one seat. Keep permission
  // sticky unless the next hook has a source-level execution id that the
  // PermissionRequest event itself does not expose.
  return true;
}

/// Orca `isClaudePermissionResumingApprovedTool`.
bool isClaudePermissionResumingApprovedTool(
  AgentStatusEvent previous,
  AgentStatusEvent next,
) {
  final previousToolUseId = _trimOrNull(previous.toolUseId);
  final nextToolUseId = _trimOrNull(next.toolUseId);
  final previousAgentId = _trimOrNull(previous.toolAgentId);
  final nextAgentId = _trimOrNull(next.toolAgentId);
  final hasAgentId = previousAgentId != null || nextAgentId != null;
  final previousAgentType = _trimOrNull(previous.toolAgentType);
  final nextAgentType = _trimOrNull(next.toolAgentType);
  final hasMatchingConcreteAgentId =
      previousAgentId != null && previousAgentId == nextAgentId;
  final hasSameExplicitAgentType =
      !hasAgentId &&
      previousAgentType != null &&
      previousAgentType == nextAgentType;
  final sameToolName =
      previous.toolName != null && previous.toolName == next.toolName;
  final sameKnownToolInput =
      previous.toolInput != null && previous.toolInput == next.toolInput;
  final sameUnknownInputFromConcreteAgent =
      hasMatchingConcreteAgentId &&
      previous.toolInput == null &&
      next.toolInput == null;
  final hasMatchingToolUseId =
      previousToolUseId != null && previousToolUseId == nextToolUseId;
  final hasConflictingToolUseId =
      previousToolUseId != null &&
      nextToolUseId != null &&
      previousToolUseId != nextToolUseId;
  final sameUnknownInputFromToolUseId =
      hasMatchingToolUseId &&
      previous.toolInput == null &&
      next.toolInput == null;

  final hook = next.hookEventName;
  return (hook == 'PreToolUse' || hook == 'PostToolUse') &&
      nextToolUseId != null &&
      !hasConflictingToolUseId &&
      // Why: subagents can share `agent_type`; a concrete agent id is the
      // strongest available signal that the permission owner resumed execution.
      // Claude's approval path omits identity but preserves the original
      // tool_use_id on PostToolUse, so that exact id is also a safe clear signal.
      (hasMatchingConcreteAgentId ||
          hasSameExplicitAgentType ||
          hasMatchingToolUseId) &&
      sameToolName &&
      (sameKnownToolInput ||
          sameUnknownInputFromConcreteAgent ||
          sameUnknownInputFromToolUseId);
}

/// Orca `shouldInheritClaudeToolUseIdForPermission`.
bool shouldInheritClaudeToolUseIdForPermission(
  AgentStatusEvent? previous,
  AgentStatusEvent next,
) {
  if (previous == null) return false;
  if (previous.state != AgentSeatAttention.working) return false;
  if (previous.hookEventName != 'PreToolUse') return false;
  final prevId = _trimOrNull(previous.toolUseId);
  if (prevId == null) return false;
  if (next.state != AgentSeatAttention.waiting) return false;
  if (next.hookEventName != 'PermissionRequest') return false;
  if (_trimOrNull(next.toolUseId) != null) return false;

  final sameKnownToolInput =
      previous.toolInput != null && previous.toolInput == next.toolInput;
  final sameUnknownToolInput =
      previous.toolInput == null && next.toolInput == null;
  if (previous.toolAgentId != next.toolAgentId ||
      previous.toolAgentType != next.toolAgentType ||
      previous.toolName == null ||
      previous.toolName != next.toolName ||
      (!sameKnownToolInput && !sameUnknownToolInput)) {
    return false;
  }
  return true;
}

/// Orca `attachClaudePermissionToolUseId`.
AgentStatusEvent attachClaudePermissionToolUseId(
  AgentStatusEvent? previous,
  AgentStatusEvent next,
) {
  final inherited = previous?.toolUseId;
  if (!shouldInheritClaudeToolUseIdForPermission(previous, next) ||
      inherited == null) {
    return next;
  }
  // Why: Claude emits PermissionRequest without tool_use_id, then reports the
  // approved command as PostToolUse with the original PreToolUse id.
  return next.copyWith(toolUseId: inherited);
}

String? _trimOrNull(String? value) {
  final t = value?.trim() ?? '';
  return t.isEmpty ? null : t;
}
