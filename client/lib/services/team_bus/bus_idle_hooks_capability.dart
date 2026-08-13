import '../cli/registry/capabilities/asset_declaring_capability.dart';
import '../cli/registry/capabilities/cli_config_asset.dart';
import '../cli/registry/capabilities/hook_registry.dart';
import 'member_bus_idle_endpoint.dart';

/// BusIdle 占位资产的 id（装配点补全时按 id 定位）。
const busIdleStopAssetId = 'bus-idle-stop';

/// mixed 模式：声明 Stop → /idle hook（blockOnDecision 语义）。
/// URL/headers 依赖运行时 [MemberBusIdleEndpoint]，装配点经
/// [completeBusIdleHooks] 补全（见 ClaudeFamilyHookRegistry.render）。
final class BusIdleHooksCapability implements AssetDeclaringCapability {
  const BusIdleHooksCapability();

  @override
  List<CliConfigAsset> get declaredAssets => [
    const CliConfigAsset<CliHookSpec>(
      kind: AssetKind.hooks,
      payload: CliHookSpec(event: 'stop', blockOnDecision: true),
      scope: AssetScope.session,
      source: AssetSource.capability,
      level: 0,
      id: busIdleStopAssetId,
    ),
  ];
}

/// 装配点补全：把 [BusIdleHooksCapability] 的占位资产（无 url/command）补成
/// 运行时 Stop → /idle http hook（claude 家族）。其余资产原样返回。
List<CliConfigAsset<CliHookSpec>> completeBusIdleHooks(
  List<CliConfigAsset<CliHookSpec>> assets, {
  required MemberBusIdleEndpoint idle,
  required String memberId,
}) {
  return [
    for (final asset in assets)
      if (asset.id == busIdleStopAssetId &&
          asset.payload.url == null &&
          asset.payload.command == null)
        CliConfigAsset<CliHookSpec>(
          kind: asset.kind,
          payload: CliHookSpec(
            event: 'stop',
            url: idle.url,
            headers: idle.headersFor(memberId),
            blockOnDecision: true,
          ),
          scope: asset.scope,
          source: asset.source,
          level: asset.level,
          id: asset.id,
        )
      else
        asset,
  ];
}
