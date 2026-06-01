import 'package:uuid/uuid.dart';

import '../../utils/logger.dart';
import 'agent_node.dart';
import 'member_launcher.dart';
import 'team_message.dart';

/// 进程内消息总线：路由 + 每成员信箱 + 状态机 + 惰性物化 + 边触发唤醒。
class TeamBus {
  TeamBus({
    required MemberLauncher launcher,
    String Function()? idGenerator,
    this.maxHop = 8,
  }) : _launcher = launcher,
       _idGenerator = idGenerator ?? (() => const Uuid().v4());

  /// 门铃文案：仅提示去 pull，不含真实内容，并标注来自 bus 而非操作者。
  static const String doorbellNotice =
      '[teammate-bus] You have unread teammate messages — call '
      'wait_for_message to read them. (From the bus, not your operator.)';

  final MemberLauncher _launcher;
  final String Function() _idGenerator;
  final int maxHop;
  final Map<String, AgentNode> _members = {};

  void declareMember(AgentNode node) {
    _members[node.memberId] = node;
  }

  AgentNode? memberById(String memberId) => _members[memberId];

  /// 长轮询接收（MCP `wait_for_message` 落点）。
  Future<List<TeamMessage>> receive(
    String memberId, {
    required Duration timeout,
  }) {
    final node = _members[memberId];
    if (node == null) {
      return Future.value(const <TeamMessage>[]);
    }
    return node.inbox.waitBatch(timeout: timeout);
  }

  /// 出站（来自成员的 send_message）。按目标状态分流投递。
  Future<void> send(TeamMessage message) async {
    if (message.hop >= maxHop) {
      appLogger.w(
        '[team-bus] dropped over-hop message ${message.id} (hop=${message.hop})',
      );
      return;
    }
    final target = _members[message.to];
    if (target == null) {
      appLogger.w(
        '[team-bus] dropped message ${message.id} to unknown member '
        '"${message.to}"',
      );
      return;
    }
    switch (target.state) {
      case MemberState.declared:
        target.state = MemberState.materializing;
        await _launcher.materialize(target.memberId, message);
        target.state = MemberState.busy;
      case MemberState.materializing:
      case MemberState.busy:
        target.inbox.deliver(message);
      case MemberState.idle:
        target.inbox.deliver(message);
        target.state = MemberState.busy;
        _launcher.wake(target.memberId, doorbellNotice);
      case MemberState.retired:
      case MemberState.dead:
        appLogger.w(
          '[team-bus] dropped message ${message.id} to ${target.memberId} '
          '(state=${target.state.name})',
        );
    }
  }

  /// idle 边：成员这一轮结束。若信箱有积压则立即门铃唤醒。
  void onMemberIdle(String memberId) {
    final node = _members[memberId];
    if (node == null) return;
    if (node.state == MemberState.retired || node.state == MemberState.dead) {
      return;
    }
    node.state = MemberState.idle;
    if (!node.inbox.isEmpty) {
      node.state = MemberState.busy;
      _launcher.wake(node.memberId, doorbellNotice);
    }
  }

  /// worker 自我退出循环。
  void leave(String memberId) {
    final node = _members[memberId];
    if (node == null) return;
    node.state = MemberState.retired;
  }
}
