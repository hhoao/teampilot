import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/claude_family_hook_registry.dart';

void main() {
  test('mergeHooksInto 并入 hooks 片段且保留其余 settings', () {
    final fragment = <String, Object?>{
      'hooks': {
        'UserPromptSubmit': [
          {
            'hooks': [
              {
                'type': 'http',
                'url': 'http://127.0.0.1:9/agent-status?event=UserPromptSubmit',
                'headers': {'X-Member': 'm'},
                'timeout': 5,
              },
            ],
          },
        ],
        'Stop': [
          {
            'hooks': [
              {
                'type': 'http',
                'url': 'http://127.0.0.1:9/idle',
                'headers': {'X-Member': 'm'},
                'timeout': 5,
              },
            ],
          },
        ],
      },
    };
    final settings = <String, Object?>{'model': 'x'};
    final merged = mergeHooksInto(settings, fragment);
    final hooks = merged['hooks'] as Map;
    expect((hooks['UserPromptSubmit'] as List), hasLength(1));
    expect((hooks['Stop'] as List), hasLength(1));
    expect(merged['model'], 'x'); // 其余 settings 保留
  });

  test('mergeHooksInto 按 (event, url) 幂等去重', () {
    final fragment = <String, Object?>{
      'hooks': {
        'Stop': [
          {
            'hooks': [
              {
                'type': 'http',
                'url': 'http://127.0.0.1:9/idle',
                'headers': {'X-Member': 'm'},
              },
            ],
          },
        ],
      },
    };
    final once = mergeHooksInto(const {}, fragment);
    final twice = mergeHooksInto(once, fragment);
    expect((twice['hooks'] as Map)['Stop'] as List, hasLength(1));
  });

  test('mergeHooksInto 空 hooks 段且原 settings 无 hooks 键 → 不写入 hooks 键', () {
    final merged =
        mergeHooksInto({'model': 'x'}, {'hooks': <String, Object?>{}});
    expect(merged.containsKey('hooks'), isFalse);
    expect(merged['model'], 'x');
  });
}
