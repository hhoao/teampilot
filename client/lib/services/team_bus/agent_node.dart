import 'mailbox.dart';

/// 成员生命周期状态。`busy` = 一轮进行中（可能 park 在 wait_for_message）；
/// `idle` = 这一轮已结束、终端挂在 prompt。
enum MemberState { declared, materializing, busy, idle, retired, dead }

/// TeamBus 对单个成员的句柄：状态 + 信箱。
class AgentNode {
  AgentNode({
    required this.memberId,
    this.state = MemberState.declared,
    Mailbox? inbox,
  }) : inbox = inbox ?? Mailbox();

  final String memberId;
  MemberState state;
  final Mailbox inbox;
}
