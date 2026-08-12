import '../cli_capability.dart';
import 'asset_declaring_capability.dart';
import 'cli_config_asset.dart';

/// 泛型核心：纯内存注册表（无 IO）。
///
/// 合并规则链（spec rev 4）：
/// 1. 不同 id → 共存追加（集合语义）
/// 2. 同 id 冲突 → scope 层级（session > workspace > team > app）
/// 3. 同 id 同 scope → source 优先级（capability > userConfig > pluginBundle > hubInstall）
/// 4. 同 id 同 scope 同 source → level（int，数值大者优先）
/// 5. 仍相同 → 后注册覆盖先注册
abstract class CliAssetRegistry<T> implements CliCapability {
  /// 追加存储，注册不做预淘汰：同 (kind, id, scope) 的多条资产共存，
  /// 由 [assetsFor] 合并阶段按规则链归并（遍历顺序即注册顺序）。
  final List<CliConfigAsset<T>> _assets = [];
  final List<void Function()> _listeners = [];

  void register(CliConfigAsset<T> asset) {
    _assets.add(asset);
    _notify();
  }

  /// 按 id 移除该资产的全部层（kind/scope 不限），与注册 API 的 id 语义一致。
  void unregister(String id) {
    final before = _assets.length;
    _assets.removeWhere((a) => a.id == id);
    if (_assets.length != before) _notify();
  }

  /// 通道 ②：从能力的声明收集。时序：必须在 registerBuiltInCliTools
  /// 完成之后统一调用一次（能力集合启动时固定）。
  void collectDeclared(Iterable<CliCapability> capabilities) {
    for (final cap in capabilities) {
      if (cap is AssetDeclaringCapability) {
        for (final asset in cap.declaredAssets) {
          if (asset is CliConfigAsset<T>) {
            register(asset);
          }
        }
      }
    }
  }

  /// 按 seat 上下文过滤（app 恒参与、作为最低优先级基底；team/workspace/session
  /// 层按对应 id 非空匹配），再对同 (kind, id) 组按规则链归并。
  List<CliConfigAsset<T>> assetsFor(AssetSeatContext seat) {
    final all = _assets.where((a) => _matchesScope(a, seat)).toList();
    final result = <CliConfigAsset<T>>[];
    for (final asset in all) {
      final i = result.indexWhere(
          (e) => e.kind == asset.kind && e.id == asset.id);
      if (i < 0) {
        result.add(asset);
        continue;
      }
      if (_winsOver(asset, result[i])) {
        result[i] = asset;
      }
    }
    return result;
  }

  bool _matchesScope(CliConfigAsset<T> a, AssetSeatContext seat) {
    switch (a.scope) {
      // app 层是全局默认层：始终参与合并（作为最低优先级基底）。
      case AssetScope.app:
        return true;
      case AssetScope.team:
        return seat.teamId.trim().isNotEmpty;
      case AssetScope.workspace:
        return seat.workspaceId.trim().isNotEmpty;
      case AssetScope.session:
        return seat.sessionId.trim().isNotEmpty;
    }
  }

  bool _winsOver(CliConfigAsset<T> a, CliConfigAsset<T> b) {
    final scopeRank = {
      AssetScope.session: 3,
      AssetScope.workspace: 2,
      AssetScope.team: 1,
      AssetScope.app: 0,
    };
    final sr = scopeRank[a.scope]!.compareTo(scopeRank[b.scope]!);
    if (sr != 0) return sr > 0;
    final sourceRank = {
      AssetSource.capability: 3,
      AssetSource.userConfig: 2,
      AssetSource.pluginBundle: 1,
      AssetSource.hubInstall: 0,
    };
    final or = sourceRank[a.source]!.compareTo(sourceRank[b.source]!);
    if (or != 0) return or > 0;
    if (a.level != b.level) return a.level > b.level;
    return true; // 后注册覆盖先注册（遍历顺序即注册顺序）
  }

  /// 增量重渲染指纹：资产集稳定 → 指纹稳定。
  ///
  /// 契约：指纹依赖 [CliConfigAsset.payload] 的 hashCode，payload 类型须提供
  /// 值语义 hashCode（内容变化必须反映为指纹变化）。
  String fingerprint(List<CliConfigAsset<T>> assets) {
    final buffer = StringBuffer();
    for (final a in assets) {
      buffer
        ..write(a.id)
        ..write('|')
        ..write(a.scope.name)
        ..write('|')
        ..write(a.source.name)
        ..write('|')
        ..write(a.level)
        ..write('|')
        ..write(a.payload.hashCode)
        ..write(';');
    }
    return buffer.toString();
  }

  void addListener(void Function() onChanged) => _listeners.add(onChanged);

  void _notify() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}
