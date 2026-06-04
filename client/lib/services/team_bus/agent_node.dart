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
