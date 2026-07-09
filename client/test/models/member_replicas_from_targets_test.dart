import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_topology.dart';

void main() {
  test('healMemberReplicasFromTargets raises stale replicas to match pins', () {
    const members = [
      TeamMemberConfig(id: 'team-lead', name: 'Lead'),
      TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 1),
    ];
    final healed = healMemberReplicasFromTargets(
      members: members,
      targets: const {
        'team-lead': 'local',
        'builder-0': 'local',
        'builder-1': 'ssh:p1',
      },
    );
    expect(healed.firstWhere((m) => m.id == 'builder').replicas, 2);
    expect(healed.firstWhere((m) => m.id == 'team-lead').replicas, 1);
  });

  test('healMemberReplicasFromTargets keeps higher profile replicas', () {
    const members = [
      TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 3),
    ];
    final healed = healMemberReplicasFromTargets(
      members: members,
      targets: const {'builder-0': 'local'},
    );
    expect(healed.single.replicas, 3);
  });
}
