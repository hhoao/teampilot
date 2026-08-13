import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_config_asset.dart';
import 'package:teampilot/services/cli/registry/capabilities/claude_family_hook_registry.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_registry.dart';

void main() {
  final registry = ClaudeFamilyHookRegistry(); // 有可变状态，不能 const

  group('ClaudeFamilyHookRegistry.render', () {
    test('http hook 渲染为 settings.json hooks 段（幂等可合并）', () {
      final out = registry.render([
        hookAsset(
          'ack',
          CliHookSpec(
            event: 'promptSubmit',
            url: 'http://127.0.0.1:1/agent-status?event=promptSubmit',
            headers: const {'X-Member': 'm1'},
            timeout: const Duration(seconds: 5),
          ),
        ),
      ]);
      final hooks = (out['settings.json'] as Map)['hooks'] as Map;
      final entries = hooks['UserPromptSubmit'] as List;
      expect(entries.single['hooks'], isA<List>());
      final h = (entries.single['hooks'] as List).single as Map;
      expect(h['type'], 'http');
      expect(h['url'], contains('/agent-status?event=promptSubmit'));
      expect(h['timeout'], 5);
    });

    test('eventNameMap: promptSubmit → UserPromptSubmit', () {
      expect(registry.eventNameMap['promptSubmit'], 'UserPromptSubmit');
      expect(registry.eventNameMap['stop'], 'Stop');
    });

    test('占位 spec（无 url/command）跳过渲染，不产生空条目', () {
      final out = registry.render([
        hookAsset(
          'bus-idle',
          const CliHookSpec(event: 'stop', blockOnDecision: true),
        ),
      ]);
      final hooks = (out['settings.json'] as Map)['hooks'] as Map;
      expect(hooks, isEmpty);
    });
  });
}

CliConfigAsset<CliHookSpec> hookAsset(String id, CliHookSpec spec) =>
    CliConfigAsset(
      kind: AssetKind.hooks,
      payload: spec,
      scope: AssetScope.app,
      source: AssetSource.capability,
      level: 0,
      id: id,
    );
