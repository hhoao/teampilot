import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/background_task_latch.dart';

void main() {
  group('isBackgroundTaskStart', () {
    test('true for PreToolUse Bash run_in_background with tool_use_id', () {
      expect(
        isBackgroundTaskStart({
          'hook_event_name': 'PreToolUse',
          'tool_name': 'Bash',
          'tool_input': {
            'command': 'ping -n 12 127.0.0.1',
            'run_in_background': true,
          },
          'tool_use_id': 'call_f766b261fd9f4358a902b8d1',
        }),
        isTrue,
      );
    });

    test('false for foreground Bash', () {
      expect(
        isBackgroundTaskStart({
          'hook_event_name': 'PreToolUse',
          'tool_name': 'Bash',
          'tool_input': {'command': 'echo hi', 'run_in_background': false},
          'tool_use_id': 'call_1',
        }),
        isFalse,
      );
    });

    test('false when run_in_background missing', () {
      expect(
        isBackgroundTaskStart({
          'hook_event_name': 'PreToolUse',
          'tool_name': 'Bash',
          'tool_input': {'command': 'echo hi'},
          'tool_use_id': 'call_1',
        }),
        isFalse,
      );
    });

    test('false for non-Bash tools (Task, Workflow, ScheduleWakeup, …)', () {
      for (final tool in ['Read', 'Task', 'Workflow', 'ScheduleWakeup']) {
        expect(
          isBackgroundTaskStart({
            'hook_event_name': 'PreToolUse',
            'tool_name': tool,
            'tool_input': {'run_in_background': true},
            'tool_use_id': 'call_1',
          }),
          isFalse,
          reason: tool,
        );
      }
    });

    test('false for PostToolUse even with the background flag', () {
      // HARD RULE (spec): PostToolUse timing is mode-dependent — it fires at
      // tool return in interactive mode and at completion in -p mode. It can
      // never start (or end) the latch.
      expect(
        isBackgroundTaskStart({
          'hook_event_name': 'PostToolUse',
          'tool_name': 'Bash',
          'tool_input': {'command': 'x', 'run_in_background': true},
          'tool_use_id': 'call_1',
        }),
        isFalse,
      );
    });

    test('false without a tool_use_id (pairing key is mandatory)', () {
      expect(
        isBackgroundTaskStart({
          'hook_event_name': 'PreToolUse',
          'tool_name': 'Bash',
          'tool_input': {'command': 'x', 'run_in_background': true},
        }),
        isFalse,
      );
    });
  });

  group('taskNotificationToolUseId', () {
    // Exact shape captured from claude 2.1.156 (spec experiment section).
    const notification = '<task-notification>\n'
        '<task-id>bi6wlgsf3</task-id>\n'
        '<tool-use-id>call_f766b261fd9f4358a902b8d1</tool-use-id>\n'
        '<output-file>C:\\tasks\\bi6wlgsf3.output</output-file>\n'
        '<status>completed</status>\n'
        '<summary>Background command completed (exit code 0)</summary>\n'
        '</task-notification>';

    test('extracts the tool-use-id from a task notification', () {
      expect(
        taskNotificationToolUseId(notification),
        'call_f766b261fd9f4358a902b8d1',
      );
    });

    test('extracts from a failed-status notification too', () {
      expect(
        taskNotificationToolUseId(
          notification.replaceFirst('completed', 'failed'),
        ),
        'call_f766b261fd9f4358a902b8d1',
      );
    });

    test('null for a real user prompt (never releases a lease)', () {
      // HARD RULE (spec): only notification-shaped prompts release.
      expect(taskNotificationToolUseId('run the tests please'), isNull);
      expect(taskNotificationToolUseId(''), isNull);
      expect(taskNotificationToolUseId(null), isNull);
      expect(
        taskNotificationToolUseId('here is a <tool-use-id>x</tool-use-id> '
            'inside a normal message'),
        isNull,
      );
    });
  });
}
