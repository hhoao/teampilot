import '../utils/team_member_naming.dart';
import 'team_config.dart';

/// A runtime instance (Pod) of a member [type] (Deployment). Holds no copy of
/// the spec — it resolves prompt/playbook/model/cli through [type]. The single
/// Deployment→Pod fan-out is [expandTeamRoster]; the runtime consumes the
/// [toMemberConfig] projection via [runtimeRosterMembers].
class MemberInstance {
  const MemberInstance({
    required this.type,
    required this.ordinal,
    required this.replicas,
  });

  final TeamMemberConfig type;

  /// 0-based position within the type's pool.
  final int ordinal;

  /// The type's effective pool size (drives the id rule).
  final int replicas;

  /// A singleton (`replicas == 1`) is named after its type; a replicated type
  /// yields `{typeId}-{ordinal}`.
  String get instanceId =>
      replicas <= 1 ? type.id : '${type.id}-$ordinal';

  String get displayName =>
      replicas <= 1 ? type.name : '${type.name} #$ordinal';

  /// Runtime projection: a [TeamMemberConfig] with `id = instanceId` and the
  /// type id seeded as a capability so [TaskRouter] routes the pool by type
  /// (and the pod by its own id, via the id-as-capability rule).
  TeamMemberConfig toMemberConfig() => type.copyWith(
        id: instanceId,
        name: displayName,
        capabilities: {type.id, ...type.capabilities},
      );
}

/// The single Deployment→Pod fan-out. The team-lead is always a singleton; any
/// other type yields `max(1, replicas)` instances.
List<MemberInstance> expandTeamRoster(List<TeamMemberConfig> members) {
  final out = <MemberInstance>[];
  for (final type in members) {
    final n = TeamMemberNaming.isTeamLead(type) || type.replicas < 1
        ? 1
        : type.replicas;
    for (var i = 0; i < n; i++) {
      out.add(MemberInstance(type: type, ordinal: i, replicas: n));
    }
  }
  return out;
}

/// Instance projections the launch/bus layers iterate in place of
/// `team.members`.
List<TeamMemberConfig> runtimeRosterMembers(TeamConfig team) =>
    [for (final inst in expandTeamRoster(team.members)) inst.toMemberConfig()];
