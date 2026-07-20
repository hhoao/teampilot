import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/claude_permission_sticky.dart';

void main() {
  group('shouldKeepClaudePermissionVisible', () {
    test('keeps waiting when another subagent reports different tool activity', () {
      final previous = AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: 'PermissionRequest',
        toolName: 'Bash',
        toolInput: 'rm -rf /tmp/orca-subagent-repro',
      );
      final next = AgentStatusEvent(
        state: AgentSeatAttention.working,
        hookEventName: 'PreToolUse',
        toolName: 'Read',
        toolInput: '/tmp/other-subagent.txt',
        toolUseId: 'toolu-other',
      );
      expect(shouldKeepClaudePermissionVisible(previous, next), isTrue);
    });

    test('keeps waiting when matching tool has no execution id', () {
      final previous = AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: 'PermissionRequest',
        toolName: 'Bash',
        toolInput: 'rm -rf /tmp/orca-subagent-repro',
      );
      final next = AgentStatusEvent(
        state: AgentSeatAttention.working,
        hookEventName: 'PreToolUse',
        toolName: 'Bash',
        toolInput: 'rm -rf /tmp/orca-subagent-repro',
      );
      expect(shouldKeepClaudePermissionVisible(previous, next), isTrue);
    });

    test('clears when same subagent starts the approved tool', () {
      final previous = AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: 'PermissionRequest',
        toolName: 'Bash',
        toolInput: 'pnpm test',
        toolAgentId: 'agent-subagent-a',
        toolAgentType: 'Review',
      );
      final next = AgentStatusEvent(
        state: AgentSeatAttention.working,
        hookEventName: 'PreToolUse',
        toolName: 'Bash',
        toolInput: 'pnpm test',
        toolAgentId: 'agent-subagent-a',
        toolAgentType: 'Review',
        toolUseId: 'toolu-approved-subagent',
      );
      expect(shouldKeepClaudePermissionVisible(previous, next), isFalse);
    });

    test('clears on UserPromptSubmit (explicit prompt)', () {
      final previous = const AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: 'PermissionRequest',
        toolName: 'Bash',
      );
      final next = const AgentStatusEvent(
        state: AgentSeatAttention.working,
        hookEventName: 'UserPromptSubmit',
        hasExplicitPrompt: true,
      );
      expect(shouldKeepClaudePermissionVisible(previous, next), isFalse);
    });

    test('clears when PostToolUse matches inherited tool_use_id', () {
      final previous = AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: 'PermissionRequest',
        toolName: 'Bash',
        toolInput: 'echo hi',
        toolUseId: 'toolu-inherited',
      );
      final next = AgentStatusEvent(
        state: AgentSeatAttention.working,
        hookEventName: 'PostToolUse',
        toolName: 'Bash',
        toolInput: 'echo hi',
        toolUseId: 'toolu-inherited',
      );
      expect(shouldKeepClaudePermissionVisible(previous, next), isFalse);
    });

    test('keeps when another same-type subagent runs same tool', () {
      final previous = AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: 'PermissionRequest',
        toolName: 'Bash',
        toolInput: 'pnpm test',
        toolAgentId: 'agent-subagent-a',
        toolAgentType: 'Review',
      );
      final next = AgentStatusEvent(
        state: AgentSeatAttention.working,
        hookEventName: 'PreToolUse',
        toolName: 'Bash',
        toolInput: 'pnpm test',
        toolAgentId: 'agent-subagent-b',
        toolAgentType: 'Review',
        toolUseId: 'toolu-other-subagent',
      );
      expect(shouldKeepClaudePermissionVisible(previous, next), isTrue);
    });
  });

  group('shouldInheritClaudeToolUseIdForPermission', () {
    test('inherits tool_use_id from matching PreToolUse onto PermissionRequest', () {
      final previous = AgentStatusEvent(
        state: AgentSeatAttention.working,
        hookEventName: 'PreToolUse',
        toolName: 'Bash',
        toolInput: 'echo hi',
        toolUseId: 'toolu-1',
      );
      final next = AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: 'PermissionRequest',
        toolName: 'Bash',
        toolInput: 'echo hi',
      );
      expect(shouldInheritClaudeToolUseIdForPermission(previous, next), isTrue);
    });
  });
}
