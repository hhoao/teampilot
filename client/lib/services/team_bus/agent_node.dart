import 'mailbox.dart';
import 'teammate_roster_profile.dart';

/// 成员生命周期状态。`busy` = 一轮进行中（可能 park 在 wait_for_message）；
/// `idle` = 这一轮已结束、终端挂在 prompt。
enum MemberState { declared, materializing, busy, idle, retired, dead }

/// TeamBus 对单个成员的句柄：状态 + 信箱 + roster 配置。
class AgentNode {
  AgentNode({
    required TeammateRosterProfile profile,
    this.state = MemberState.declared,
    Mailbox? inbox,
  }) : profile = profile,
       inbox = inbox ?? Mailbox();

  /// 兼容测试：仅 member id + 可选 state。
  factory AgentNode.test({
    required String memberId,
    MemberState state = MemberState.declared,
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
      state: state,
    );
  }

  final TeammateRosterProfile profile;
  MemberState state;
  final Mailbox inbox;

  String get memberId => profile.memberId;
}
