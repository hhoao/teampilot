import '../../models/team_config.dart';
import '../../models/workspace_topology.dart';
import 'team_member_naming.dart';

class MembersMachineGroup {
  const MembersMachineGroup({
    required this.targetId,
    required this.members,
  });

  final String targetId;
  final List<TeamMemberConfig> members;
}

/// Resolve pin for grouping: missing/empty → `local`; else trimmed target id.
String resolveMemberMachineTargetId(
  MemberTargetAssignments memberTargets,
  String memberId,
) {
  final raw = memberTargetForInstanceId(memberTargets, memberId);
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return 'local';
  return trimmed;
}

/// Groups [members] by resolved target. Group order: lead's machine first,
/// then first-seen target order. Within group: lead first, else roster order.
List<MembersMachineGroup> groupMembersByMachine({
  required List<TeamMemberConfig> members,
  required MemberTargetAssignments memberTargets,
}) {
  final buckets = <String, List<TeamMemberConfig>>{};
  final order = <String>[];
  String? leadTarget;

  for (final m in members) {
    final tid = resolveMemberMachineTargetId(memberTargets, m.id);
    if (TeamMemberNaming.isTeamLead(m)) leadTarget = tid;
    buckets.putIfAbsent(tid, () {
      order.add(tid);
      return <TeamMemberConfig>[];
    }).add(m);
  }

  final sortedKeys = [...order];
  if (leadTarget != null) {
    sortedKeys
      ..remove(leadTarget)
      ..insert(0, leadTarget);
  }

  return [
    for (final tid in sortedKeys)
      MembersMachineGroup(
        targetId: tid,
        members: _leadFirst(buckets[tid]!),
      ),
  ];
}

List<TeamMemberConfig> _leadFirst(List<TeamMemberConfig> list) {
  final lead = list.where(TeamMemberNaming.isTeamLead).toList();
  final rest = list.where((m) => !TeamMemberNaming.isTeamLead(m)).toList();
  return [...lead, ...rest];
}
