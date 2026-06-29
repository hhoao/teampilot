import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/member_instance.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/runtime_roster_cache.dart';

TeamProfile team(List<TeamMemberConfig> members) => TeamProfile(
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

  test('workspaceion seeds the type id as a capability', () {
    final inst = expandTeamRoster(const [
      TeamMemberConfig(
          id: 'builder', name: 'Builder', replicas: 2,
          capabilities: {'rust'}),
    ]).first;
    final cfg = inst.toMemberConfig();
    expect(cfg.id, 'builder-0');
    expect(cfg.capabilities, {'builder', 'rust'});
    // a workspaceion is a single concrete pod, not itself re-expandable
    expect(cfg.replicas, 1);
  });

  test('runtimeRosterMembers workspaces every instance', () {
    final members = runtimeRosterMembers(team(const [
      TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
    ]));
    expect(members.map((m) => m.id), ['team-lead', 'builder-0', 'builder-1']);
  });

  test('RuntimeRosterCache returns the same list for the same team', () {
    final cache = RuntimeRosterCache();
    final profile = team(const [
      TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
    ]);

    final first = cache.resolve(profile);
    final second = cache.resolve(profile);
    expect(identical(first, second), isTrue);
  });

  test('RuntimeRosterCache clears when replicas change', () {
    final cache = RuntimeRosterCache();
    final base = team(const [
      TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 1),
    ]);
    final expanded = team(const [
      TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
    ]);

    expect(cache.resolve(base), hasLength(1));
    cache.clear();
    expect(cache.resolve(expanded), hasLength(2));
  });
}
