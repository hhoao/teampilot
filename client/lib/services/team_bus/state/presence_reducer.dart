import '../member_state.dart';
import 'bus_effect.dart';
import 'bus_event.dart';
import 'presence.dart';

/// reducer 的上下文:成员 id（用于产出带 id 的效果）+ 信箱是否有未读。
class PresenceContext {
  const PresenceContext({required this.memberId, required this.hasUnread});
  final String memberId;
  final bool hasUnread;
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
        return _to(s.copyWith(
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.turnDoneReady,
        ));

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

      case MailArrived(:final eager):
        return _onMail(s, ctx, eager: eager);

      case WaitEntered():
        if (!s.ptyRunning) return _stay(s);
        return _to(s.copyWith(activity: MemberActivity.turnDoneBusWait));

      case WaitExited():
        if (s.ptyRunning && s.isParked) {
          return _to(s.copyWith(activity: MemberActivity.active));
        }
        return _stay(s);

      case TurnEnded():
        // declared / materializing / parked 不处理(由调用方守卫,这里也兜底)。
        if (!s.ptyRunning ||
            s.lifecycle == MemberLifecycle.materializing ||
            s.isParked) {
          return _stay(s);
        }
        final ready = s.copyWith(activity: MemberActivity.turnDoneReady);
        if (!ctx.hasUnread) return _to(ready);
        return PresenceTransition(
          ready.copyWith(activity: MemberActivity.active),
          [DoorbellEffect(ctx.memberId)],
        );
    }
  }

  static PresenceTransition _onMail(
    Presence s,
    PresenceContext ctx, {
    required bool eager,
  }) {
    // declared 无 PTY:仅同步 mailQueued / none,不响门铃。
    if (s.lifecycle == MemberLifecycle.declared) {
      return _to(s.copyWith(
        activity: ctx.hasUnread
            ? MemberActivity.mailQueued
            : MemberActivity.none,
      ));
    }
    // 已 park:waiter 直接收,绝不注入门铃。
    if (s.isParked) return _stay(s);
    if (!s.ptyRunning || !ctx.hasUnread) return _stay(s);

    // eager(idle-notify / 用户命令):即便 active 也响。
    // 非 eager(send):仅 idle-at-prompt 响,不打断进行中的回合。
    final shouldDoorbell = eager || s.atPrompt;
    if (!shouldDoorbell) return _stay(s);
    return PresenceTransition(
      s.copyWith(activity: MemberActivity.active),
      [DoorbellEffect(ctx.memberId)],
    );
  }

  static PresenceTransition _to(Presence next) =>
      PresenceTransition(next, const []);
  static PresenceTransition _stay(Presence s) =>
      PresenceTransition(s, const []);
}
