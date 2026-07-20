import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/agent_status_normalizer.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';

void main() {
  group('AgentStatusNormalizer', () {
    test('Claude PermissionRequest → waiting', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'PermissionRequest', 'tool_name': 'Bash'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('Claude AskUserQuestion PreToolUse → waiting', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.claude,
        body: {
          'hook_event_name': 'PreToolUse',
          'tool_name': 'AskUserQuestion',
        },
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('Claude Stop → done', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'Stop'},
      );
      expect(e?.state, AgentSeatAttention.done);
    });

    test('Claude UserPromptSubmit → working', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'UserPromptSubmit'},
      );
      expect(e?.state, AgentSeatAttention.working);
    });

    test('Claude PostToolUse → working (clears wait)', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'PostToolUse', 'tool_name': 'Bash'},
      );
      expect(e?.state, AgentSeatAttention.working);
    });

    test('flashskyai uses Claude-family rules', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.flashskyai,
        body: {'hook_event_name': 'PermissionRequest'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('Codex PermissionRequest → waiting', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.codex,
        body: {'hook_event_name': 'PermissionRequest'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('OpenCode permission.asked → waiting', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.opencode,
        body: {'event': 'permission.asked'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('OpenCode question.asked → waiting', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.opencode,
        body: {'event': 'question.asked'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('OpenCode session.idle → done', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.opencode,
        body: {'event': 'session.idle'},
      );
      expect(e?.state, AgentSeatAttention.done);
    });

    test('corrupt / unknown → null', () {
      expect(
        AgentStatusNormalizer.normalize(cli: CliTool.claude, body: {}),
        isNull,
      );
    });
  });
}
