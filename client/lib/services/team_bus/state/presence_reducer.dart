import '../member_state.dart';
import 'bus_effect.dart';
import 'bus_event.dart';
import 'presence.dart';

/// reducer 的上下文:成员 id（用于产出带 id 的效果）+ 信箱是否有未读。
class PresenceContext {
  const PresenceContext({
    required this.memberId,
    required this.hasUnread,
    this.doorbelled = false,
  });
  final String memberId;
  final bool hasUnread;

  /// 本轮未读是否已经响过门铃（见 [AgentNode.doorbelled]）。为真时 [MailArrived]
  /// 不再重复注入。
  final bool doorbelled;
}

/// 一次跃迁的结果:新在线态 + 待落地的效果列表。
class PresenceTransition {
  const PresenceTransition(this.presence, this.effects);
  final Presence presence;
  final List<BusEffect> effects;
}

/// **纯函数状态机**:`(Presence, BusEvent, ctx) → (Presence, effects)`。
///
/// 全部合法跃迁与门铃决策集中此一处,可审、可零 fake 单测。取代旧实现里散落在
/// `send` / `receivePending` / `onMemberIdle` / `_wakeMemberForMail` /
/// `_syncDeclaredInboxActivity` 的命令式赋值。
///
/// Mermaid 流程图见 [TEAM_BUS_MEMBER_STATE.md](../../../../../docs/TEAM_BUS_MEMBER_STATE.md)。
abstract final class PresenceReducer {
  PresenceReducer._();

  static PresenceTransition reduce(
    Presence s,
    BusEvent event,
    PresenceContext ctx,
  ) {
    switch (event) {
      case PtySpawned():
        // Late spawn callback must not clobber an in-flight active turn (e.g.
        // MaterializeCompleted won the race during PTY connect).
        final activity = s.activity == MemberActivity.active
            ? MemberActivity.active
            : MemberActivity.turnDoneReady;
        return _to(
          s.copyWith(lifecycle: MemberLifecycle.running, activity: activity),
        );

      case MaterializeStarted(:final bootstrap):
        if (s.lifecycle != MemberLifecycle.declared) return _stay(s);
        return PresenceTransition(
          s.copyWith(lifecycle: MemberLifecycle.materializing),
          [MaterializeEffect(ctx.memberId, bootstrap)],
        );

      case MaterializeCompleted():
        return PresenceTransition(
          s.copyWith(
            lifecycle: MemberLifecycle.running,
            activity: MemberActivity.active,
          ),
          [DoorbellEffect(ctx.memberId)],
        );

      case MailArrived():
        return _onMail(s, ctx);

      case WaitEntered():
        if (!s.ptyRunning) return _stay(s);
        return _to(s.copyWith(activity: MemberActivity.turnDoneBusWait));

      case WaitExited(:final resumeActive):
        if (s.ptyRunning && s.isParked) {
          return _to(
            s.copyWith(
              activity: resumeActive
                  ? MemberActivity.active
                  : MemberActivity.turnDoneReady,
            ),
          );
        }
        return _stay(s);

      case TurnStarted():
        // 用户在 prompt 直接提交 → working。未 running / 物化中 / 已 parked 不处理
        // (parked 由 wait/mail 唤醒路径接管,不在这里抢)。已 active 则原地不动。
        if (!s.ptyRunning ||
            s.lifecycle == MemberLifecycle.materializing ||
            s.isParked) {
          return _stay(s);
        }
        return _to(s.copyWith(activity: MemberActivity.active));

      case TurnEnded():
        // declared / materializing / parked 不处理(由调用方守卫,这里也兜底)。
        if (!s.ptyRunning ||
            s.lifecycle == MemberLifecycle.materializing ||
            s.isParked) {
          return _stay(s);
        }
        // 回合结束 → prompt。门铃只走 [MailArrived]（[onMemberIdle] 在落态后补发）。
        if (s.activity != MemberActivity.active) return _stay(s);
        return _to(s.copyWith(activity: MemberActivity.turnDoneReady));

      case PtyClosed():
        // 空闲回收:PTY 被丢弃 → 复位为 declared(保留 inbox)。activity 依未读落到
        // none / mailQueued,之后 materialize 漏斗按需重拉。
        if (!s.ptyRunning) return _stay(s);
        return _to(
          s.copyWith(
            lifecycle: MemberLifecycle.declared,
            activity: ctx.hasUnread
                ? MemberActivity.mailQueued
                : MemberActivity.none,
          ),
        );
    }
  }

  static PresenceTransition _onMail(Presence s, PresenceContext ctx) {
    // declared 无 PTY:仅同步 mailQueued / none,不响门铃。
    if (s.lifecycle == MemberLifecycle.declared) {
      return _to(
        s.copyWith(
          activity: ctx.hasUnread
              ? MemberActivity.mailQueued
              : MemberActivity.none,
        ),
      );
    }
    // 已 park:waiter 直接收,绝不注入门铃。
    if (s.isParked) return _stay(s);
    if (!s.ptyRunning || !ctx.hasUnread) return _stay(s);

    // 仅 idle-at-prompt 响,不打断进行中的回合。
    if (!s.atPrompt) return _stay(s);
    // 已响过一记「去 read_messages」、worker 尚未消费 → 不重复注入：back-to-back
    // 邮件会把同一条提示打好几遍。真没送达（回车被吞）由看门狗重敲兜底。
    if (ctx.doorbelled) return _stay(s);
    // Doorbell = TeamPilot 判定 worker 应处理 teammate 信；presence 保持 at-prompt，
    // delivery 维度单独跟踪（mailbox-delivery spec）。
    return PresenceTransition(s, [DoorbellEffect(ctx.memberId)]);
  }

  static PresenceTransition _to(Presence next) =>
      PresenceTransition(next, const []);
  static PresenceTransition _stay(Presence s) =>
      PresenceTransition(s, const []);
}
