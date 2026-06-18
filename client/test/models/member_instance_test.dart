import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/member_instance.dart';
import 'package:teampilot/models/team_config.dart';

TeamIdentity team(List<TeamMemberConfig> members) => TeamIdentity(
      id: 'team-1',
      name: 'T',
      cli: CliTool.claude,
      teamMode: TeamMode.mixed,
      members: members,
    );

void main() {
  test('singleton type → one instance whose id is the type id', () {
    final insts = expandTeamRoster(const [
      TeamMemberConfig(id: 'builder', name: 'Builder'),
    ]);
    expect(insts.single.instanceId, 'builder');
    expect(insts.single.displayName, 'Builder');
  });

  test('replicated type → N numbered instances', () {
    final insts = expandTeamRoster(const [
      TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 3),
    ]);
    expect(insts.map((i) => i.instanceId), ['builder-0', 'builder-1', 'builder-2']);
    expect(insts.map((i) => i.displayName),
        ['Builder #0', 'Builder #1', 'Builder #2']);
  });

  test('the team-lead is always a singleton regardless of replicas', () {
    final insts = expandTeamRoster(const [
      TeamMemberConfig(id: 'team-lead', name: 'team-lead', replicas: 5),
    ]);
    expect(insts.single.instanceId, 'team-lead');
  });

  test('projection seeds the type id as a capability', () {
    final inst = expandTeamRoster(const [
      TeamMemberConfig(
          id: 'builder', name: 'Builder', replicas: 2,
          capabilities: {'rust'}),
    ]).first;
    final cfg = inst.toMemberConfig();
    expect(cfg.id, 'builder-0');
    expect(cfg.capabilities, {'builder', 'rust'});
    // a projection is a single concrete pod, not itself re-expandable
    expect(cfg.replicas, 1);
  });

  test('runtimeRosterMembers projects every instance', () {
    final members = runtimeRosterMembers(team(const [
      TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
    ]));
    expect(members.map((m) => m.id), ['team-lead', 'builder-0', 'builder-1']);
  });
}
