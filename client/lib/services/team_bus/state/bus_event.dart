import '../team_message.dart';

/// 喂给 [PresenceReducer] 的事件:成员生命周期 / 活动态的每一次「发生了什么」。
/// 取代散落在 TeamBus 各方法里的命令式字段赋值。
sealed class BusEvent {
  const BusEvent();
}

/// PTY 已 spawn 起来(扩展侧 markMemberRunning）。
class PtySpawned extends BusEvent {
  const PtySpawned();
}

/// 出站 send 命中 declared 成员:开始物化(declared → materializing)。
class MaterializeStarted extends BusEvent {
  const MaterializeStarted(this.bootstrap);
  final TeamMessage bootstrap;
}

/// 物化完成(materializing → running，进入首个回合)。
class MaterializeCompleted extends BusEvent {
  const MaterializeCompleted();
}

/// 有消息落入信箱。[eager] 为真时即便成员正在回合中(active）也响门铃
/// (idle-notify / 用户命令路径);为假时仅在 idle-at-prompt 才响(send 路径，
/// 不打断进行中的回合)。
class MailArrived extends BusEvent {
  const MailArrived({this.eager = false});
  final bool eager;
}

/// 成员进入 MCP `wait_for_message` 阻塞。
class WaitEntered extends BusEvent {
  const WaitEntered();
}

/// 成员退出 `wait_for_message`(收到批次 / 超时 / 取消)。
class WaitExited extends BusEvent {
  const WaitExited();
}

/// 回合结束的 idle 边(Stop hook / 终端 watcher）。
class TurnEnded extends BusEvent {
  const TurnEnded();
}

/// 用户在成员自己的 prompt 直接提交一行(**未** parked 在 `wait_for_message`)
/// → 回合开始的 working 边。把"用户驱动 leader 开新回合"这个事件接回 bus，让
/// presence 不必再靠 PTY 字节(被 spinner 重绘污染)去猜 working。
class TurnStarted extends BusEvent {
  const TurnStarted();
}
