import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/extension/effect/settings_hook_effect_applier.dart';

void main() {
  const applier = SettingsHookEffectApplier();

  Map<String, Object?> merge(Map<String, Object?> base) =>
      applier.mergeIntoSettings(
        base: base,
        event: 'PreToolUse',
        matcher: 'Bash',
        hookCommand: 'bash /path/rtk-rewrite.sh',
        marker: 'rtk-rewrite',
      );

  test('inserts a PreToolUse/Bash hook when none exists', () {
    final result = merge({});
    final hooks = result['hooks'] as Map<String, Object?>;
    final pre = hooks['PreToolUse'] as List;
    expect(pre, hasLength(1));
    final entry = pre.single as Map;
    expect(entry['matcher'], 'Bash');
    final inner = entry['hooks'] as List;
    expect((inner.single as Map)['command'], 'bash /path/rtk-rewrite.sh');
  });

  test('is idempotent — does not double-insert when marker present', () {
    final once = merge({});
    final twice = merge(once);
    final hooks = twice['hooks'] as Map<String, Object?>;
    expect((hooks['PreToolUse'] as List), hasLength(1));
  });

  test('prepends without dropping existing PreToolUse entries', () {
    final base = {
      'hooks': {
        'PreToolUse': [
          {
            'matcher': 'Edit',
            'hooks': [
              {'type': 'command', 'command': 'echo keep'},
            ],
          },
        ],
      },
    };
    final result = merge(base);
    final pre = (result['hooks'] as Map)['PreToolUse'] as List;
    expect(pre, hasLength(2));
    expect((pre.first as Map)['matcher'], 'Bash');
    expect((pre.last as Map)['matcher'], 'Edit');
  });

  test('preserves unrelated top-level settings keys', () {
    final result = merge({'model': 'sonnet'});
    expect(result['model'], 'sonnet');
  });
}
