import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team/rtk_settings_merge.dart';

void main() {
  group('RtkSettingsMerge', () {
    test('adds hooks.PreToolUse when absent', () {
      const merge = RtkSettingsMerge();
      final out = merge.mergeIntoSettings(
        base: {'skipDangerousModePermissionPrompt': true},
        hookCommand: 'bash "/tmp/hooks/rtk-rewrite.sh"',
      );
      final hooks = out['hooks'] as Map;
      final pre = hooks['PreToolUse'] as List;
      expect(pre, hasLength(1));
      expect((pre.first as Map)['matcher'], 'Bash');
    });

    test('is idempotent when RTK hook already present', () {
      const merge = RtkSettingsMerge();
      final base = {
        'hooks': {
          'PreToolUse': [
            {
              'matcher': 'Bash',
              'hooks': [
                {
                  'type': 'command',
                  'command': 'bash "/tmp/hooks/rtk-rewrite.sh"',
                },
              ],
            },
          ],
        },
      };
      final out = merge.mergeIntoSettings(
        base: base,
        hookCommand: 'bash "/tmp/hooks/rtk-rewrite.sh"',
      );
      expect(out, base);
    });

    test('prepends RTK before existing PreToolUse matchers', () {
      const merge = RtkSettingsMerge();
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
        hookCommand: 'bash "/tmp/rtk.sh"',
      );
      final pre = (out['hooks'] as Map)['PreToolUse'] as List;
      expect(pre, hasLength(2));
      final firstHooks = (pre.first as Map)['hooks'] as List;
      expect(firstHooks.first, isA<Map>());
      expect(
        (firstHooks.first as Map)['command'],
        contains('rtk'),
      );
    });
  });
}
