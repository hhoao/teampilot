import 'member_inbox.dart';
import 'member_state.dart';
import 'teammate_roster_profile.dart';

export 'member_state.dart';

/// TeamBus 对单个成员的句柄。
class AgentNode {
  AgentNode({
    required this.profile,
    this.lifecycle = MemberLifecycle.declared,
    this.activity = MemberActivity.none,
    MemberInbox? inbox,
  }) : inbox = inbox ?? MemberInbox(memberId: profile.memberId);

  factory AgentNode.test({
    required String memberId,
    MemberLifecycle lifecycle = MemberLifecycle.declared,
    MemberActivity activity = MemberActivity.none,
    String? displayName,
    String? cli,
    bool isTeamLead = false,
  }) {
    return AgentNode(
      profile: TeammateRosterProfile.minimal(
        memberId,
        displayName: displayName,
        cli: cli,
        isTeamLead: isTeamLead,
      ),
      lifecycle: lifecycle,
      activity: activity,
    );
  }

  final TeammateRosterProfile profile;
  MemberLifecycle lifecycle;
  MemberActivity activity;
  final MemberInbox inbox;

  /// 门铃幂等闸：本轮「有未读」已经响过一次门铃了吗。turn 结束往往被 **两个独立
  /// 信源** 同时上报（CLI Stop-hook `/idle` + 1s 终端活动 watcher 的 working→idle
  /// 边，外加注入门铃自身引起的活动抖动），每次 `onMemberIdle` 都会跑 `TurnEnded`。
  /// 没有这个闸，同一条未读会被注入 2+ 次「你有未读」提示。响一次后置位，成员真正
  /// 进入 `wait_for_message`（[MemberInbox] 消费路径）时清零 —— 读完后新邮件照常再响。
  bool doorbelled = false;

  String get memberId => profile.memberId;

  bool get ptyRunning =>
      lifecycle == MemberLifecycle.materializing ||
      lifecycle == MemberLifecycle.running;

  /// MCP `wait_for_message` 阻塞中（PTY 已运行）。
  bool get waitingForMessage => activity.isBusWaitBlocked;

  /// Claude `TeamFile.members[].isActive`。
  bool? get claudeIsActive => switch (lifecycle) {
    MemberLifecycle.running => activity.claudeIsActive,
    _ => null,
  };

  String get busPhaseLabel => activity.busPhaseLabel;
}
