import 'agent_node.dart';
import 'teammate_roster_profile.dart';

/// MCP `list_teammates` 返回的成员快照（配置 + bus 运行时）。
class TeammateSnapshot {
  const TeammateSnapshot({
    required this.profile,
    required this.state,
    required this.unreadCount,
    required this.waitingForMessage,
    required this.ptyRunning,
  });

  final TeammateRosterProfile profile;
  final MemberState state;
  final int unreadCount;
  final bool waitingForMessage;
  final bool ptyRunning;

  String get memberId => profile.memberId;
}

/// MCP `list_teammates` 完整响应（团队头 + 成员列表）。
class TeamRosterSnapshot {
  const TeamRosterSnapshot({
    this.team,
    required this.members,
  });

  final TeamSessionContext? team;
  final List<TeammateSnapshot> members;
}
