import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/cli/registry/capabilities/chat_interaction_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

AgentStatusEvent? normalize({
  required CliTool cli,
  required Map<String, Object?> body,
}) => CliToolRegistry.builtIn()
    .capability<ChatInteractionCapability>(cli)
    ?.normalize(body);

void main() {
  group('AgentStatusNormalizer', () {
    test('Claude PermissionRequest → waiting', () {
      final e = normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'PermissionRequest', 'tool_name': 'Bash'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('Claude AskUserQuestion PreToolUse → waiting', () {
      final e = normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'PreToolUse', 'tool_name': 'AskUserQuestion'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('Claude ExitPlanMode PreToolUse → waiting', () {
      final e = normalize(
        cli: CliTool.claude,
        body: {
          'hook_event_name': 'PreToolUse',
          'tool_name': 'ExitPlanMode',
          'tool_use_id': 'toolu-plan-1',
          'tool_input': {
            'plan': '1. Refactor the launcher.\n2. Add tests.',
            'planFilePath': '/tmp/plan.md',
          },
        },
      );
      expect(e?.state, AgentSeatAttention.waiting);
      expect(e?.toolName, 'ExitPlanMode');
      expect(e?.toolUseId, 'toolu-plan-1');
      expect(e?.planText, '1. Refactor the launcher.\n2. Add tests.');
      expect(e?.planFilePath, '/tmp/plan.md');
    });

    test('exit_plan_mode PreToolUse → waiting (casing variants)', () {
      final e = normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'PreToolUse', 'tool_name': 'exit_plan_mode'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('Claude Stop → done', () {
      final e = normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'Stop'},
      );
      expect(e?.state, AgentSeatAttention.done);
    });

    test('Claude UserPromptSubmit → working', () {
      final e = normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'UserPromptSubmit'},
      );
      expect(e?.state, AgentSeatAttention.working);
    });

    test('Claude PostToolUse → working (clears wait)', () {
      final e = normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'PostToolUse', 'tool_name': 'Bash'},
      );
      expect(e?.state, AgentSeatAttention.working);
    });

    test('Claude PreToolUse (non-AskUserQuestion) → working (clears wait)', () {
      final e = normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'PreToolUse', 'tool_name': 'Bash'},
      );
      expect(e?.state, AgentSeatAttention.working);
    });

    test('Claude PostToolUseFailure → working (clears wait)', () {
      final e = normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'PostToolUseFailure', 'tool_name': 'Bash'},
      );
      expect(e?.state, AgentSeatAttention.working);
    });

    test('Claude StopFailure → done', () {
      final e = normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'StopFailure'},
      );
      expect(e?.state, AgentSeatAttention.done);
    });

    test('ask_user_question PreToolUse → waiting (casing variants)', () {
      final e = normalize(
        cli: CliTool.claude,
        body: {
          'hook_event_name': 'PreToolUse',
          'tool_name': 'ask_user_question',
        },
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('flashskyai uses Claude-family rules', () {
      final e = normalize(
        cli: CliTool.flashskyai,
        body: {'hook_event_name': 'PermissionRequest'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('Codex PermissionRequest → waiting', () {
      final e = normalize(
        cli: CliTool.codex,
        body: {'hook_event_name': 'PermissionRequest'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('OpenCode permission.asked → waiting', () {
      final e = normalize(
        cli: CliTool.opencode,
        body: {'event': 'permission.asked'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('OpenCode permission.asked parses payload for chat card', () {
      final e = normalize(
        cli: CliTool.opencode,
        body: {
          'event': 'permission.asked',
          'request_id': 'perm-1',
          'session_id': 'ses_abc',
          'permission': 'Run `npm install`',
          'patterns': ['npm'],
          'always': ['npm', 'npm install'],
          'tool': {'messageID': 'msg-1', 'callID': 'call-1'},
        },
      );
      expect(e?.state, AgentSeatAttention.waiting);
      expect(e?.hookEventName, 'permission.asked');
      expect(e?.askRequestId, 'perm-1');
      expect(e?.nativeSessionId, 'ses_abc');
      expect(e?.permissionRequest, isNotNull);
      final p = e!.permissionRequest!;
      expect(p.id, 'perm-1');
      expect(p.description, 'Run `npm install`');
      expect(p.patterns, ['npm']);
      expect(p.always.map((option) => option.label).toList(), [
        'npm',
        'npm install',
      ]);
      expect(p.sessionID, 'ses_abc');
      expect(p.toolMessageID, 'msg-1');
      expect(p.toolCallID, 'call-1');
    });

    test(
      'OpenCode permission.asked without id keeps waiting without card data',
      () {
        final e = normalize(
          cli: CliTool.opencode,
          body: {'event': 'permission.asked', 'permission': 'Run tests'},
        );
        expect(e?.state, AgentSeatAttention.waiting);
        expect(e?.askRequestId, isNull);
        // No correlation id → no answerable card payload.
        expect(e?.permissionRequest, isNull);
      },
    );

    test('OpenCode question.asked → waiting', () {
      final e = normalize(
        cli: CliTool.opencode,
        body: {'event': 'question.asked'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
      expect(e?.askUserQuestions, isNull);
    });

    test('OpenCode question.asked parses questions for chat card', () {
      final e = normalize(
        cli: CliTool.opencode,
        body: {
          'event': 'question.asked',
          'request_id': 'req-1',
          'questions': [
            {
              'question': 'Which stack?',
              'options': [
                {'label': 'Flutter', 'explanation': 'Cross-platform UI'},
                {'label': 'React'},
              ],
              'multiple': false,
            },
          ],
        },
      );
      expect(e?.state, AgentSeatAttention.waiting);
      expect(e?.askUserQuestions, hasLength(1));
      expect(e?.askUserQuestions?.single.question, 'Which stack?');
      expect(e?.askUserQuestions?.single.options, hasLength(2));
      expect(
        e?.askUserQuestions?.single.options.first.description,
        'Cross-platform UI',
      );
      expect(e?.askUserQuestions?.single.multiSelect, isFalse);
    });

    test('opencode question.asked keeps request_id and session_id', () {
      final e = normalize(
        cli: CliTool.opencode,
        body: {
          'event': 'question.asked',
          'questions': [
            {
              'question': 'Pick one?',
              'options': [
                {'label': 'A'},
                {'label': 'B'},
              ],
            },
          ],
          'request_id': 'req_1',
          'session_id': 'ses_abc',
        },
      );
      expect(e?.askRequestId, 'req_1');
      expect(e?.nativeSessionId, 'ses_abc');
      expect(e?.askUserQuestions, isNotNull);
    });

    test('opencode question.asked accepts id / sessionID aliases', () {
      final e = normalize(
        cli: CliTool.opencode,
        body: {
          'event': 'question.asked',
          'id': 'req_alias',
          'sessionID': 'ses_alias',
          'questions': [
            {
              'question': 'Pick one?',
              'options': [
                {'label': 'A'},
              ],
            },
          ],
        },
      );
      expect(e?.askRequestId, 'req_alias');
      expect(e?.nativeSessionId, 'ses_alias');
    });

    test('opencode question.reply_failed restores signal', () {
      final e = normalize(
        cli: CliTool.opencode,
        body: {
          'event': 'question.reply_failed',
          'request_id': 'req_1',
          'message': 'boom',
        },
      );
      expect(e?.hookEventName, 'question.reply_failed');
      expect(e?.askRequestId, 'req_1');
      expect(e?.restoreAskWaiting, isTrue);
      expect(e?.message, 'boom');
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('opencode question.reply_failed without request_id skips restore', () {
      final e = normalize(
        cli: CliTool.opencode,
        body: {'event': 'question.reply_failed', 'message': 'missing id'},
      );
      expect(e?.hookEventName, 'question.reply_failed');
      expect(e?.askRequestId, isNull);
      expect(e?.restoreAskWaiting, isFalse);
      expect(e?.message, 'missing id');
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('opencode question.answered → working with request id', () {
      final e = normalize(
        cli: CliTool.opencode,
        body: {
          'event': 'question.answered',
          'request_id': 'req_1',
          'session_id': 'ses_1',
        },
      );
      expect(e?.state, AgentSeatAttention.working);
      expect(e?.hookEventName, 'question.answered');
      expect(e?.askRequestId, 'req_1');
      expect(e?.nativeSessionId, 'ses_1');
    });

    test('opencode permission.answered → working with request id', () {
      final e = normalize(
        cli: CliTool.opencode,
        body: {'event': 'permission.answered', 'request_id': 'per_1'},
      );
      expect(e?.state, AgentSeatAttention.working);
      expect(e?.hookEventName, 'permission.answered');
      expect(e?.askRequestId, 'per_1');
    });

    test(
      'Claude AskUserQuestion PreToolUse sets askRequestId from tool_use_id',
      () {
        final e = normalize(
          cli: CliTool.claude,
          body: {
            'hook_event_name': 'PreToolUse',
            'tool_name': 'AskUserQuestion',
            'tool_use_id': 'toolu-q1',
            'tool_input': {
              'questions': [
                {
                  'question': 'OK?',
                  'options': ['Yes', 'No'],
                },
              ],
            },
          },
        );
        expect(e?.state, AgentSeatAttention.waiting);
        expect(e?.toolUseId, 'toolu-q1');
        expect(e?.askRequestId, 'toolu-q1');
        expect(e?.askUserQuestions, isNotNull);
      },
    );

    test('OpenCode session.idle → done', () {
      final e = normalize(
        cli: CliTool.opencode,
        body: {'event': 'session.idle'},
      );
      expect(e?.state, AgentSeatAttention.done);
    });

    test('opencode userMessageSubmitted → working + prompt', () {
      final e = normalize(
        cli: CliTool.opencode,
        body: {'event': 'userMessageSubmitted', 'prompt': '1'},
      );
      expect(e?.state, AgentSeatAttention.working);
      expect(e?.prompt, '1');
    });

    test('Cursor preToolUse → working with tool info', () {
      final e = normalize(
        cli: CliTool.cursor,
        body: {
          'hook_event_name': 'preToolUse',
          'tool_name': 'Shell',
          'tool_use_id': 'toolu-c1',
        },
      );
      expect(e?.state, AgentSeatAttention.working);
      expect(e?.toolName, 'Shell');
      expect(e?.toolUseId, 'toolu-c1');
    });

    test('Cursor postToolUse / beforeSubmitPrompt → working', () {
      for (final event in [
        'postToolUse',
        'postToolUseFailure',
        'beforeSubmitPrompt',
        'afterAgentResponse',
        'beforeShellExecution',
        'beforeMCPExecution',
      ]) {
        final e = normalize(
          cli: CliTool.cursor,
          body: {'hook_event_name': event},
        );
        expect(e?.state, AgentSeatAttention.working, reason: event);
      }
    });

    test('Cursor stop → done', () {
      final e = normalize(
        cli: CliTool.cursor,
        body: {'hook_event_name': 'stop'},
      );
      expect(e?.state, AgentSeatAttention.done);
    });

    test('Cursor unknown / empty → null', () {
      expect(
        normalize(cli: CliTool.cursor, body: {'hook_event_name': 'weird'}),
        isNull,
      );
      expect(normalize(cli: CliTool.cursor, body: {}), isNull);
    });

    test('corrupt / unknown → null', () {
      expect(normalize(cli: CliTool.claude, body: {}), isNull);
    });

    // Why working (not null): the attention cubit tracks child ids and keeps
    // the parent seat working until every subagent stops — a child completion
    // must reach the cubit instead of being dropped here.
    test('Codex SubagentStart and SubagentStop retain the child id', () {
      for (final name in ['SubagentStart', 'SubagentStop']) {
        final event = normalize(
          cli: CliTool.codex,
          body: {'hook_event_name': name, 'agent_id': 'child-a'},
        );
        expect(event?.hookEventName, name);
        expect(event?.toolAgentId, 'child-a');
        expect(event?.state, AgentSeatAttention.working);
      }
    });

    test('Subagent lifecycle without agent id stays working', () {
      for (final name in ['SubagentStart', 'SubagentStop']) {
        final event = normalize(
          cli: CliTool.codex,
          body: {'hook_event_name': name},
        );
        expect(event?.hookEventName, name);
        expect(event?.toolAgentId, isNull);
        expect(event?.state, AgentSeatAttention.working);
      }
    });

    test('SubagentStart / SubagentStop on Claude stay working', () {
      for (final name in ['SubagentStart', 'SubagentStop']) {
        final e = normalize(
          cli: CliTool.claude,
          body: {'hook_event_name': name, 'agent_id': 'child-a'},
        );
        expect(e?.hookEventName, name);
        expect(e?.toolAgentId, 'child-a');
        expect(e?.state, AgentSeatAttention.working);
      }
    });

    test('extracts tool_use_id / agent_id / tool input preview', () {
      final e = normalize(
        cli: CliTool.claude,
        body: {
          'hook_event_name': 'PreToolUse',
          'tool_name': 'Bash',
          'tool_input': {'command': 'pnpm test'},
          'tool_use_id': 'toolu-1',
          'agent_id': 'agent-a',
          'agent_type': 'Review',
        },
      );
      expect(e?.state, AgentSeatAttention.working);
      expect(e?.toolInput, 'pnpm test');
      expect(e?.toolUseId, 'toolu-1');
      expect(e?.toolAgentId, 'agent-a');
      expect(e?.toolAgentType, 'Review');
      expect(e?.hookEventName, 'PreToolUse');
    });

    test('UserPromptSubmit sets hasExplicitPrompt', () {
      final e = normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'UserPromptSubmit'},
      );
      expect(e?.hasExplicitPrompt, isTrue);
    });

    test('Claude UserPromptSubmit 携带 prompt 原文', () {
      final e = normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'UserPromptSubmit', 'prompt': '1'},
      );
      expect(e?.prompt, '1');
    });

    test('非 UserPromptSubmit 事件 prompt 为 null', () {
      final e = normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'Stop'},
      );
      expect(e?.prompt, isNull);
    });

    test('Cursor beforeSubmitPrompt 透传 prompt（实测 payload schema）', () {
      // 实测取证（cursor 2026.08.04，headless cursor-agent 与 GUI 一致）：
      // executeHookForStep(beforeSubmitPrompt, {conversation_id,
      // generation_id, model, prompt, attachments, composer_mode}) 然后
      // {...args, hook_event_name, cursor_version, workspace_roots,
      // user_email, transcript_path} 整体作为 stdin payload。
      final e = normalize(
        cli: CliTool.cursor,
        body: {
          'conversation_id': 'conv-1',
          'generation_id': 'gen-1',
          'model': 'gpt-5.6-sol',
          'prompt': 'fix the flaky test',
          'attachments': [
            {'type': 'file', 'file_path': '/tmp/a.ts'},
          ],
          'composer_mode': 'normal',
          'hook_event_name': 'beforeSubmitPrompt',
          'cursor_version': '2026.08.04',
          'workspace_roots': ['/home/user/repo'],
          'user_email': 'u@example.com',
        },
      );
      expect(e?.state, AgentSeatAttention.working);
      expect(e?.prompt, 'fix the flaky test');
      expect(e?.hookEventName, 'beforeSubmitPrompt');
      expect(e?.toolName, isNull);
    });
  });
}
