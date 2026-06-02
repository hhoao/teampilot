import 'mailbox.dart';
import 'member_state.dart';
import 'teammate_roster_profile.dart';

export 'member_state.dart';

/// TeamBus 对单个成员的句柄。
class AgentNode {
  AgentNode({
    required this.profile,
    this.lifecycle = MemberLifecycle.declared,
    this.activity = MemberActivity.none,
    Mailbox? inbox,
  }) : inbox = inbox ?? Mailbox();

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
  final Mailbox inbox;

  /// Set when this member receives real work (any inbound message), cleared
  /// when it next reports idle to the leader. Gates worker→leader idle
  /// notifications to one ping per dispatched batch: a freshly-launched,
  /// never-tasked worker never pings the leader (and thus the doorbell), and a
  /// busy worker does not re-ping on every idle edge until it is tasked again.
  bool hasUnreportedWork = false;

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

  /// send 到 running + [MemberActivity.turnDoneReady] 时立刻 doorbell。
  bool get acceptsImmediateDoorbell =>
      lifecycle == MemberLifecycle.running &&
      activity == MemberActivity.turnDoneReady;

  /// send 时只入队、不 writeln。
  bool get shouldEnqueueMailOnly =>
      lifecycle == MemberLifecycle.materializing ||
      (lifecycle == MemberLifecycle.running &&
          (activity == MemberActivity.active || activity.isBusWaitBlocked));
}
