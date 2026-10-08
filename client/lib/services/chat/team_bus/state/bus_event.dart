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

/// 空闲回收:PTY 被丢弃(running|materializing → declared)。inbox 保留,消息不丢。
class PtyClosed extends BusEvent {
  const PtyClosed();
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

/// 有消息落入信箱。门铃仅在 idle-at-prompt 响，不打断进行中的回合。
class MailArrived extends BusEvent {
  const MailArrived();
}

/// 成员进入 MCP `wait_for_message` 阻塞。
class WaitEntered extends BusEvent {
  const WaitEntered();
}

/// 成员退出 `wait_for_message`(收到批次 / 超时 / 取消)。
///
/// [resumeActive] 为真时升到 [MemberActivity.active]（本次 wait 带回了消息、
/// 任务，或 MCP `notifications/cancelled` 超时后 agent loop 继续）；为假时回到
/// [MemberActivity.turnDoneReady]（空醒 / 断连 / session stop）。
class WaitExited extends BusEvent {
  const WaitExited({this.resumeActive = false});
  final bool resumeActive;
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
