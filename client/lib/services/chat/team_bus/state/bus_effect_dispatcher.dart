import '../member_launcher.dart';
import 'bus_effect.dart';

/// 把 [BusEffect] 数据落地成真实副作用(拉 PTY / 注入 stdin）。这是 reducer 纯函数
/// 世界与 I/O 世界之间的唯一桥。换传输只换它,不动状态机。
class BusEffectDispatcher {
  BusEffectDispatcher({
    required MemberLauncher launcher,
    required String doorbellNotice,
  }) : _launcher = launcher,
       _doorbellNotice = doorbellNotice;

  final MemberLauncher _launcher;
  final String _doorbellNotice;

  Future<void> dispatch(BusEffect effect) async {
    switch (effect) {
      case DoorbellEffect(:final memberId):
        _launcher.wake(memberId, _doorbellNotice);
      case MaterializeEffect(:final memberId, :final bootstrap):
        await _launcher.materialize(memberId, bootstrap);
    }
  }

  Future<void> dispatchAll(Iterable<BusEffect> effects) async {
    for (final effect in effects) {
      await dispatch(effect);
    }
  }
}
