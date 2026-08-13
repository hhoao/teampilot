import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_config_asset.dart';
import 'package:teampilot/services/cli/registry/capabilities/claude_family_hook_registry.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_registry.dart';

void main() {
  test('ClaudeFamilyHookRegistry 渲染结果可并入 settings.json', () {
    final r = ClaudeFamilyHookRegistry();
    final rendered = r.render([
      // 模拟 agent-status 的 8 事件中的 UserPromptSubmit + Stop
      _asset('agent-status', CliHookSpec(
        event: 'promptSubmit',
        url: 'http://127.0.0.1:9/agent-status?event=UserPromptSubmit',
        headers: const {'X-Member': 'm'},
        timeout: const Duration(seconds: 5),
      )),
      _asset('bus-idle', CliHookSpec(
        event: 'stop',
        url: 'http://127.0.0.1:9/idle',
        headers: const {'X-Member': 'm'},
      )),
    ]);
    final settings = <String, Object?>{'model': 'x'};
    final merged =
        mergeHooksInto(settings, rendered['settings.json'] as Map<String, Object?>);
    final hooks = merged['hooks'] as Map;
    expect((hooks['UserPromptSubmit'] as List), hasLength(1));
    expect((hooks['Stop'] as List), hasLength(1));
    expect(merged['model'], 'x'); // 其余 settings 保留
  });

  test('mergeHooksInto 空 hooks 段且原 settings 无 hooks 键 → 不写入 hooks 键', () {
    final merged =
        mergeHooksInto({'model': 'x'}, {'hooks': <String, Object?>{}});
    expect(merged.containsKey('hooks'), isFalse);
    expect(merged['model'], 'x');
  });
}

CliConfigAsset<CliHookSpec> _asset(String id, CliHookSpec spec) =>
    CliConfigAsset(
      kind: AssetKind.hooks,
      payload: spec,
      scope: AssetScope.app,
      source: AssetSource.capability,
      level: 0,
      id: id,
    );
