import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_lead_settings_merge.dart';

void main() {
  group('TeamLeadSettingsMerge', () {
    const hookCommand =
        'bash "/tmp/hooks/teampilot-deny-team-lead-self-message.sh"';

    test('adds PreToolUse hooks for SendMessage, TaskUpdate, and Agent', () {
      const merge = TeamLeadSettingsMerge();
      final out = merge.mergeIntoSettings(
        base: const {'permissions': {'deny': ['Bash']}},
        hookCommand: hookCommand,
      );
      final pre = (out['hooks'] as Map)['PreToolUse'] as List;
      expect(pre, hasLength(3));
      for (final matcher in TeamLeadSettingsMerge.guardedTools) {
        final entry = pre.cast<Map>().firstWhere(
          (e) => e['matcher'] == matcher,
        );
        final command =
            ((entry['hooks'] as List).first as Map)['command'] as String;
        expect(command, contains('teampilot-deny-team-lead-self-message'));
      }
    });

    test('is idempotent when all guarded hooks already present', () {
      const merge = TeamLeadSettingsMerge();
      final base = {
        'hooks': {
          'PreToolUse': [
            for (final matcher in TeamLeadSettingsMerge.guardedTools)
              {
                'matcher': matcher,
                'hooks': [
                  {'type': 'command', 'command': hookCommand},
                ],
              },
          ],
        },
      };
      final out = merge.mergeIntoSettings(
        base: base,
        hookCommand: hookCommand,
      );
      expect(out, base);
    });

    test('backfills TaskUpdate and Agent when only SendMessage hook exists', () {
      const merge = TeamLeadSettingsMerge();
      final base = {
        'hooks': {
          'PreToolUse': [
            {
              'matcher': 'SendMessage',
              'hooks': [
                {'type': 'command', 'command': hookCommand},
              ],
            },
          ],
        },
      };
      final out = merge.mergeIntoSettings(
        base: base,
        hookCommand: hookCommand,
      );
      final pre = (out['hooks'] as Map)['PreToolUse'] as List;
      expect(pre, hasLength(3));
      expect(
        pre.map((e) => (e as Map)['matcher']),
        ['SendMessage', 'TaskUpdate', 'Agent'],
      );
    });

    test('appends after existing PreToolUse matchers', () {
      const merge = TeamLeadSettingsMerge();
      final base = {
        'hooks': {
          'PreToolUse': [
            {
              'matcher': 'Bash',
              'hooks': [
                {'type': 'command', 'command': 'echo other'},
              ],
            },
          ],
        },
      };
      final out = merge.mergeIntoSettings(
        base: base,
        hookCommand: hookCommand,
      );
      final pre = (out['hooks'] as Map)['PreToolUse'] as List;
      expect(pre, hasLength(4));
      expect(
        pre.skip(1).map((e) => (e as Map)['matcher']),
        TeamLeadSettingsMerge.guardedTools,
      );
    });
  });
}
