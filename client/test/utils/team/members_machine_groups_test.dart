import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/utils/team/members_machine_groups.dart';
import 'package:teampilot/utils/team/team_member_naming.dart';

TeamMemberConfig _m(String id, {String name = ''}) => TeamMemberConfig(
  id: id,
  name: name.isEmpty ? id : name,
);

void main() {
  test('single target → one group (caller decides flat UI)', () {
    final members = [_m(TeamMemberNaming.teamLeadName), _m('dev')];
    final groups = groupMembersByMachine(
      members: members,
      memberTargets: {
        TeamMemberNaming.teamLeadName: 'local',
        'dev': 'local',
      },
    );
    expect(groups, hasLength(1));
    expect(groups.single.targetId, 'local');
  });

  test('two targets → lead machine first; lead within group first', () {
    final lead = _m(TeamMemberNaming.teamLeadName);
    final a = _m('a');
    final b = _m('b');
    // roster order: a, lead, b — lead on ssh, a/b on local
    final groups = groupMembersByMachine(
      members: [a, lead, b],
      memberTargets: {
        'a': 'local',
        TeamMemberNaming.teamLeadName: 'ssh:p1',
        'b': 'local',
      },
    );
    expect(groups.map((g) => g.targetId).toList(), ['ssh:p1', 'local']);
    expect(groups.first.members.map((m) => m.id), [TeamMemberNaming.teamLeadName]);
    expect(groups.last.members.map((m) => m.id), ['a', 'b']);
  });

  test('missing pin → local bucket', () {
    final groups = groupMembersByMachine(
      members: [_m('dev'), _m('ops')],
      memberTargets: {'ops': 'ssh:p1'},
    );
    expect(groups.map((g) => g.targetId).toSet(), {'local', 'ssh:p1'});
    expect(
      groups.firstWhere((g) => g.targetId == 'local').members.single.id,
      'dev',
    );
  });

  test('unknown non-empty targetId kept as bucket key', () {
    final groups = groupMembersByMachine(
      members: [_m('dev'), _m('ops')],
      memberTargets: {
        'dev': 'ssh:gone',
        'ops': 'local',
      },
    );
    expect(groups.map((g) => g.targetId).toSet(), {'ssh:gone', 'local'});
  });
}
