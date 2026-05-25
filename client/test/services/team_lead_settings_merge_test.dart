import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_lead_settings_merge.dart';

void main() {
  group('TeamLeadSettingsMerge', () {
    test('adds SendMessage PreToolUse hook when absent', () {
      const merge = TeamLeadSettingsMerge();
      final out = merge.mergeIntoSettings(
        base: const {'permissions': {'deny': ['Bash']}},
        hookCommand:
            'bash "/tmp/hooks/teampilot-deny-team-lead-self-message.sh"',
      );
      final hooks = out['hooks'] as Map;
      final pre = hooks['PreToolUse'] as List;
      expect(pre, hasLength(1));
      expect((pre.first as Map)['matcher'], 'SendMessage');
      final command =
          (((pre.first as Map)['hooks'] as List).first as Map)['command']
              as String;
      expect(command, contains('teampilot-deny-team-lead-self-message'));
    });

    test('is idempotent when hook already present', () {
      const merge = TeamLeadSettingsMerge();
      final base = {
        'hooks': {
          'PreToolUse': [
            {
              'matcher': 'SendMessage',
              'hooks': [
                {
                  'type': 'command',
                  'command':
                      'bash "/tmp/hooks/teampilot-deny-team-lead-self-message.sh"',
                },
              ],
            },
          ],
        },
      };
      final out = merge.mergeIntoSettings(
        base: base,
        hookCommand:
            'bash "/tmp/hooks/teampilot-deny-team-lead-self-message.sh"',
      );
      expect(out, base);
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
        hookCommand: 'bash "/tmp/teampilot-deny-team-lead-self-message.sh"',
      );
      final pre = (out['hooks'] as Map)['PreToolUse'] as List;
      expect(pre, hasLength(2));
      expect((pre.last as Map)['matcher'], 'SendMessage');
    });
  });
}
