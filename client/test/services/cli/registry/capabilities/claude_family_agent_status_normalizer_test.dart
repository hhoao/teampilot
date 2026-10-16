import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/cli/registry/capabilities/claude_family_agent_status_normalizer.dart';

void main() {
  group('ClaudeFamilyAgentStatusNormalizer', () {
    test(
      'PermissionRequest for a general tool carries a permissionRequest payload',
      () {
        final status = const ClaudeFamilyAgentStatusNormalizer().normalize({
          'hook_event_name': 'PermissionRequest',
          'tool_name': 'Bash',
          'tool_input': {'command': 'rm -rf node_modules'},
          'permission_suggestions': [
            {
              'type': 'addRules',
              'rules': [
                {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
              ],
              'behavior': 'allow',
              'destination': 'localSettings',
            },
          ],
        });
        expect(status, isNotNull);
        expect(status!.state, AgentSeatAttention.waiting);
        expect(status.permissionRequest, isNotNull);
        expect(status.permissionRequest!.description, contains('Bash'));
        expect(status.permissionRequest!.always, hasLength(1));
        expect(
          status.permissionRequest!.always.first.label,
          'Bash(rm -rf node_modules)',
        );
      },
    );

    test(
      'PermissionRequest for ExitPlanMode carries no permissionRequest payload',
      () {
        final status = const ClaudeFamilyAgentStatusNormalizer().normalize({
          'hook_event_name': 'PermissionRequest',
          'tool_name': 'ExitPlanMode',
          'tool_input': {'plan': 'Do the thing'},
        });
        expect(status, isNotNull);
        expect(status!.state, AgentSeatAttention.waiting);
        expect(status.permissionRequest, isNull);
        expect(status.planText, isNotNull); // plan card path, unchanged
      },
    );

    test(
      'PermissionRequest for AskUserQuestion keeps the question payload',
      () {
        final status = const ClaudeFamilyAgentStatusNormalizer().normalize({
          'hook_event_name': 'PermissionRequest',
          'tool_name': 'AskUserQuestion',
          'tool_input': {
            'questions': [
              {
                'question': 'Continue?',
                'options': ['Yes', 'No'],
              },
            ],
          },
        });
        expect(status, isNotNull);
        expect(status!.state, AgentSeatAttention.waiting);
        expect(status.permissionRequest, isNull);
        expect(status.askUserQuestions, isNotNull);
        expect(status.askUserQuestions!.first.question, 'Continue?');
      },
    );
  });

  group('background task lease signals', () {
    test('PreToolUse Bash run_in_background flags backgroundTaskStarted', () {
      final status = const ClaudeFamilyAgentStatusNormalizer().normalize({
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Bash',
        'tool_input': {
          'command': 'ping -n 12 127.0.0.1',
          'run_in_background': true,
        },
        'tool_use_id': 'call_f766b261fd9f4358a902b8d1',
      });
      expect(status, isNotNull);
      expect(status!.state, AgentSeatAttention.working);
      expect(status.backgroundTaskStarted, isTrue);
      expect(status.toolUseId, 'call_f766b261fd9f4358a902b8d1');
      expect(status.taskNotificationToolUseId, isNull);
    });

    test('foreground Bash PreToolUse does not flag', () {
      final status = const ClaudeFamilyAgentStatusNormalizer().normalize({
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Bash',
        'tool_input': {'command': 'echo hi'},
        'tool_use_id': 'call_1',
      });
      expect(status!.backgroundTaskStarted, isFalse);
    });

    test('UserPromptSubmit task notification carries the release id', () {
      final status = const ClaudeFamilyAgentStatusNormalizer().normalize({
        'hook_event_name': 'UserPromptSubmit',
        'prompt':
            '<task-notification>\n'
            '<task-id>bi6wlgsf3</task-id>\n'
            '<tool-use-id>call_f766b261fd9f4358a902b8d1</tool-use-id>\n'
            '<status>completed</status>\n'
            '</task-notification>',
      });
      expect(status, isNotNull);
      expect(status!.state, AgentSeatAttention.working);
      expect(status.hasExplicitPrompt, isTrue);
      expect(status.taskNotificationToolUseId, 'call_f766b261fd9f4358a902b8d1');
      expect(status.backgroundTaskStarted, isFalse);
    });

    test('real user prompt carries no release id', () {
      final status = const ClaudeFamilyAgentStatusNormalizer().normalize({
        'hook_event_name': 'UserPromptSubmit',
        'prompt': 'how is the test run going?',
      });
      expect(status!.taskNotificationToolUseId, isNull);
    });

    test('task notification without a tool-use-id falls back to task-id', () {
      // `background_tasks[].id` is a task id, not a tool_use_id — releasing a
      // snapshot lease needs the `<task-id>` when no `<tool-use-id>` is sent.
      final status = const ClaudeFamilyAgentStatusNormalizer().normalize({
        'hook_event_name': 'UserPromptSubmit',
        'prompt':
            '<task-notification>\n'
            '<task-id>bi6wlgsf3</task-id>\n'
            '<status>completed</status>\n'
            '</task-notification>',
      });
      expect(status!.taskNotificationToolUseId, 'bi6wlgsf3');
    });
  });

  group('background_tasks snapshot (Stop / SubagentStop)', () {
    test('Stop with in-flight tasks carries their ids', () {
      final status = const ClaudeFamilyAgentStatusNormalizer().normalize({
        'hook_event_name': 'Stop',
        'background_tasks': [
          {'id': 't1', 'type': 'shell', 'status': 'running'},
          {'id': 't2', 'type': 'subagent', 'status': 'running'},
        ],
      });
      expect(status, isNotNull);
      expect(status!.state, AgentSeatAttention.done);
      expect(status.inFlightTaskIds, ['t1', 't2']);
    });

    test('Stop with an empty snapshot carries an empty list', () {
      final status = const ClaudeFamilyAgentStatusNormalizer().normalize({
        'hook_event_name': 'Stop',
        'background_tasks': <Object?>[],
      });
      expect(status!.inFlightTaskIds, isEmpty);
    });

    test('Stop without the field carries null (unknown)', () {
      final status = const ClaudeFamilyAgentStatusNormalizer().normalize({
        'hook_event_name': 'Stop',
      });
      expect(status!.inFlightTaskIds, isNull);
    });

    test('non-Stop events never carry the snapshot', () {
      final status = const ClaudeFamilyAgentStatusNormalizer().normalize({
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Read',
        'background_tasks': [
          {'id': 't1', 'type': 'shell'},
        ],
      });
      expect(status!.inFlightTaskIds, isNull);
    });
  });
}
