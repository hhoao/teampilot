import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_asset_registry.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_config_asset.dart';

void main() {
  group('CliAssetRegistry merge', () {
    test('不同 id 共存追加（集合语义）', () {
      final r = _TestRegistry();
      r.register(_asset('a', AssetScope.app));
      r.register(_asset('b', AssetScope.app));
      final out = r.assetsFor(_seat());
      expect(out.map((a) => a.id), containsAll(['a', 'b']));
    });

    test('同 id 冲突：scope 主序 session > workspace > team > app', () {
      final r = _TestRegistry();
      r.register(_asset('x', AssetScope.app, payload: 'app-payload'));
      r.register(_asset('x', AssetScope.session, payload: 'session-payload'));
      final out = r.assetsFor(_seat());
      expect(out.single.payload, 'session-payload');
    });

    test('同 id 同 scope：source 次序 capability > userConfig', () {
      final r = _TestRegistry();
      r.register(
          _asset('x', AssetScope.app, payload: 'user', source: AssetSource.userConfig));
      r.register(
          _asset('x', AssetScope.app, payload: 'cap', source: AssetSource.capability));
      expect(r.assetsFor(_seat()).single.payload, 'cap');
    });

    test('同 id 同 scope 同 source：level 数值大者优先', () {
      final r = _TestRegistry();
      r.register(_asset('x', AssetScope.app, payload: 'low', level: 1));
      r.register(_asset('x', AssetScope.app, payload: 'high', level: 9));
      expect(r.assetsFor(_seat()).single.payload, 'high');
    });

    test('unregister 后资产消失；指纹随资产集变化', () {
      final r = _TestRegistry();
      r.register(_asset('a', AssetScope.app));
      final f1 = r.fingerprint(r.assetsFor(_seat()));
      r.unregister('a');
      final f2 = r.fingerprint(r.assetsFor(_seat()));
      expect(f1, isNot(f2));
      expect(r.assetsFor(_seat()), isEmpty);
    });
  });
}

class _TestRegistry extends CliAssetRegistry<String> {}

CliConfigAsset<String> _asset(
  String id,
  AssetScope scope, {
  String payload = 'p',
  AssetSource source = AssetSource.capability,
  int level = 0,
}) =>
    CliConfigAsset(
      kind: AssetKind.hooks,
      payload: payload,
      scope: scope,
      source: source,
      level: level,
      id: id,
    );

AssetSeatContext _seat() => const AssetSeatContext(
      sessionId: 's1',
      teamId: 't1',
      workspaceId: 'w1',
      memberId: '',
    );
