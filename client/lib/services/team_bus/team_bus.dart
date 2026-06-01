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
}
