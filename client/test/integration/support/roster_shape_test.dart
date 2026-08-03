import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/member_instance.dart';
import 'package:teampilot/models/team_config.dart';

import 'roster_shape.dart';

void main() {
  test('singleton team: developer replicas 1 → pods team-lead, developer', () {
    final team = buildMatrixTeam(
      tool: CliTool.claude,
      mode: TeamMode.native,
      shape: RosterShape.singleton,
    );
    expect(team.members.map((m) => m.id), ['team-lead', 'developer']);
    expect(team.members.last.replicas, 1);
    expect(
      expandTeamRoster(team.members).map((i) => i.instanceId),
      ['team-lead', 'developer'],
    );
  });

  test('replicated team: developer replicas 2 → pods developer-0/1', () {
    final team = buildMatrixTeam(
      tool: CliTool.claude,
      mode: TeamMode.native,
      shape: RosterShape.replicated,
    );
    expect(team.members.last.replicas, 2);
    expect(
      expandTeamRoster(team.members).map((i) => i.instanceId),
      ['team-lead', 'developer-0', 'developer-1'],
    );
  });

  test('placementFiltered omits developer-1 from bindings helper', () {
    final team = buildMatrixTeam(
      tool: CliTool.claude,
      mode: TeamMode.native,
      shape: RosterShape.placementFiltered,
    );
    final bindings = matrixSessionBindings(
      shape: RosterShape.placementFiltered,
      team: team,
    );
    expect(bindings.map((b) => b.rosterMemberId), [
      'team-lead',
      'developer-0',
    ]);
  });

  test('matrixExpectedPodIds matches expand for each shape', () {
    expect(
      matrixExpectedPodIds(RosterShape.singleton),
      ['team-lead', 'developer'],
    );
    expect(
      matrixExpectedPodIds(RosterShape.replicated),
      ['team-lead', 'developer-0', 'developer-1'],
    );
    expect(
      matrixExpectedPodIds(RosterShape.placementFiltered),
      ['team-lead', 'developer-0'],
    );
  });

  test('matrixPrimaryWorkerPodId', () {
    expect(matrixPrimaryWorkerPodId(RosterShape.singleton), 'developer');
    expect(matrixPrimaryWorkerPodId(RosterShape.replicated), 'developer-0');
    expect(matrixPrimaryWorkerPodId(RosterShape.placementFiltered), 'developer-0');
  });
}
