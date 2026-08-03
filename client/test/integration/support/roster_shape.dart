import 'package:teampilot/models/member_instance.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/utils/team/team_member_naming.dart';

const kMatrixLeadMemberId = 'team-lead';
const kMatrixWorkerTypeId = 'developer';

const kMatrixLeaderProviderId = 'mock-leader';
const kMatrixWorkerProviderId = 'mock-worker';

String matrixMockModelIdFor(String providerId) => '$providerId-model';

/// Matrix roster topology axis (CLI × Mode × RosterShape).
enum RosterShape {
  /// Lead + one worker type with replicas=1.
  singleton,

  /// Worker type replicas≥2 → session/CLI pods `type-0`, `type-1`, …
  replicated,

  /// Session bindings omit some expanded pods (Machines / placement).
  placementFiltered,
}

/// Builds a homogeneous matrix team for [tool] and [mode] with roster [shape].
TeamProfile buildMatrixTeam({
  required CliTool tool,
  required TeamMode mode,
  required RosterShape shape,
}) {
  final replicas = switch (shape) {
    RosterShape.singleton => 1,
    RosterShape.replicated || RosterShape.placementFiltered => 2,
  };
  return TeamProfile(
    id: 'it-matrix-${tool.value}-${mode.value}',
    name: 'IT Matrix ${tool.value} ${mode.value}',
    cli: tool,
    teamMode: mode,
    members: [
      TeamMemberConfig(
        id: kMatrixLeadMemberId,
        name: TeamMemberNaming.teamLeadName,
        provider: kMatrixLeaderProviderId,
        model: matrixMockModelIdFor(kMatrixLeaderProviderId),
        cli: tool,
        effort: 'low',
      ),
      TeamMemberConfig(
        id: kMatrixWorkerTypeId,
        name: kMatrixWorkerTypeId,
        provider: kMatrixWorkerProviderId,
        model: matrixMockModelIdFor(kMatrixWorkerProviderId),
        cli: tool,
        effort: 'low',
        replicas: replicas,
      ),
    ],
  );
}

/// Session pod ids after expand / placement filter for [shape].
List<String> matrixExpectedPodIds(RosterShape shape) => switch (shape) {
  RosterShape.singleton => [kMatrixLeadMemberId, kMatrixWorkerTypeId],
  RosterShape.replicated => [
    kMatrixLeadMemberId,
    '$kMatrixWorkerTypeId-0',
    '$kMatrixWorkerTypeId-1',
  ],
  RosterShape.placementFiltered => [
    kMatrixLeadMemberId,
    '$kMatrixWorkerTypeId-0',
  ],
};

/// Primary worker pod id for gateway scripts / compose targeting.
String matrixPrimaryWorkerPodId(RosterShape shape) => switch (shape) {
  RosterShape.singleton => kMatrixWorkerTypeId,
  RosterShape.replicated || RosterShape.placementFiltered =>
    '$kMatrixWorkerTypeId-0',
};

/// Session member bindings for [team] after roster expand (and shape filter).
List<SessionMemberBinding> matrixSessionBindings({
  required RosterShape shape,
  required TeamProfile team,
}) {
  final omitted = switch (shape) {
    RosterShape.placementFiltered => {'$kMatrixWorkerTypeId-1'},
    RosterShape.singleton || RosterShape.replicated => <String>{},
  };
  return [
    for (final inst in expandTeamRoster(team.members))
      if (!omitted.contains(inst.instanceId))
        SessionMemberBinding(
          rosterMemberId: inst.instanceId,
          typeId: inst.type.id,
          taskId: 'matrix-task-${inst.instanceId}',
          cli: inst.type.cli ?? team.cli,
        ),
  ];
}
