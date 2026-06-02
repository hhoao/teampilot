import 'agent_node.dart';
import 'teammate_roster_profile.dart';

/// MCP `list_teammates` 返回的成员快照。
class TeammateSnapshot {
  const TeammateSnapshot({
    required this.profile,
    required this.lifecycle,
    required this.activity,
    required this.unreadCount,
  });

  final TeammateRosterProfile profile;
  final MemberLifecycle lifecycle;
  final MemberActivity activity;
  final int unreadCount;

  String get memberId => profile.memberId;

  bool get waitingForMessage => activity.isBusWaitBlocked;

  bool get ptyRunning =>
      lifecycle == MemberLifecycle.materializing ||
      lifecycle == MemberLifecycle.running;

  bool? get claudeIsActive => switch (lifecycle) {
    MemberLifecycle.running => activity.claudeIsActive,
    _ => null,
  };

  String get busPhaseLabel => activity.busPhaseLabel;
}

class TeamRosterSnapshot {
  const TeamRosterSnapshot({
    this.team,
    required this.members,
  });

  final TeamSessionContext? team;
  final List<TeammateSnapshot> members;
}
