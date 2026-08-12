import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_config_asset.dart';
import 'package:teampilot/services/cli/registry/capabilities/claude_family_hook_registry.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_registry.dart';
import 'package:teampilot/services/cli/registry/config_profile/bus_idle_stop_hook.dart';
import 'package:teampilot/services/team_bus/bus_idle_hooks_capability.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';

void main() {
  test('BusIdleHooksCapability 声明 stop → /idle 资产', () {
    const cap = BusIdleHooksCapability();
    final assets = cap.declaredAssets;
    expect(assets, hasLength(1));
    final a = assets.single;
    expect(a.kind, AssetKind.hooks);
    expect(a.scope, AssetScope.session);
    expect(a.source, AssetSource.capability);
    expect(a.id, busIdleStopAssetId);
    expect(a.payload.url, isNull);
    expect(a.payload.command, isNull);
  });

  test('completeBusIdleHooks 用运行时 endpoint 补全占位资产（装配点）', () {
    const cap = BusIdleHooksCapability();
    const idle = MemberBusIdleEndpoint(
      url: 'http://127.0.0.1:9/idle',
      sessionId: 's1',
    );
    final completed = completeBusIdleHooks(
      cap.declaredAssets.cast<CliConfigAsset<CliHookSpec>>(),
      idle: idle,
      memberId: 'm1',
    );
    final spec = completed.single.payload;
    expect(spec.event, 'stop');
    expect(spec.url, 'http://127.0.0.1:9/idle');
    expect(spec.blockOnDecision, isTrue);
    expect(spec.headers['X-Member'], 'm1');
  });

  test('collectDeclared → 装配点补全 → render → 与旧 mergeStopIdleHook 幂等去重', () {
    final hookRegistry = ClaudeFamilyHookRegistry();
    hookRegistry.collectDeclared(const [BusIdleHooksCapability()]);
    const seat = AssetSeatContext(
      sessionId: 's1',
      teamId: 't1',
      workspaceId: 'w1',
      memberId: 'm1',
    );
    var assets = hookRegistry.assetsFor(seat);
    expect(assets.map((a) => a.id), [busIdleStopAssetId]);

    // 未补全的占位资产（无 url/command）不渲染出空条目
    final emptyRender = hookRegistry.render(assets);
    expect((emptyRender['settings.json'] as Map)['hooks'], isEmpty);

    // 装配点补全后渲染出 Stop http hook
    const idle = MemberBusIdleEndpoint(
      url: 'http://127.0.0.1:9/idle',
      sessionId: 's1',
    );
    assets = completeBusIdleHooks(assets, idle: idle, memberId: 'm1');
    final rendered = hookRegistry.render(assets);
    final stop =
        ((rendered['settings.json'] as Map)['hooks'] as Map)['Stop'] as List;
    expect(stop, hasLength(1));
    final h = ((stop.single['hooks']) as List).single as Map;
    expect(h['url'], 'http://127.0.0.1:9/idle');

    // 与旧通道（mergeStopIdleHook）输出合并 → 同 URL 幂等去重，仍只有一个
    final old = mergeStopIdleHook(const {}, 'm1', idle);
    final merged = mergeHooksInto(
      old,
      rendered['settings.json'] as Map<String, Object?>,
    );
    expect((merged['hooks'] as Map)['Stop'] as List, hasLength(1));
  });
}
