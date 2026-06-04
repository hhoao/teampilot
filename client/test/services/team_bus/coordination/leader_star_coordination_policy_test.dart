import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/coordination/coordination_policy.dart';
import 'package:teampilot/services/team_bus/coordination/leader_star_coordination_policy.dart';
import 'package:teampilot/services/team_bus/env/bus_environment.dart';
import 'package:teampilot/services/team_bus/idle_notification.dart';

class _FakeView implements CoordinationView {
  _FakeView(this._members, this.teamLeadId);
  final Map<String, AgentNode> _members;
  @override
  final String? teamLeadId;
  @override
  AgentNode? member(String memberId) => _members[memberId];
}

void main() {
  late LeaderStarCoordinationPolicy policy;
  late _FakeView view;

  setUp(() {
    var seq = 0;
    policy = LeaderStarCoordinationPolicy(
      environment: BusEnvironment(ids: () => 'id${seq++}', clock: () => 0),
    );
    view = _FakeView(
      {
        'lead': AgentNode.test(memberId: 'lead', isTeamLead: true),
        'dev': AgentNode.test(memberId: 'dev', displayName: 'Dev'),
      },
      'lead',
    );
  });

  test('no notification when the worker has no inbound work', () {
    expect(policy.onMemberIdle(view, 'dev'), isEmpty);
  });

  test('worker with inbound work notifies the leader once per batch', () {
    policy.noteInboundWork('dev');

    final first = policy.onMemberIdle(view, 'dev');
    expect(first, hasLength(1));
    expect(first.single.to, 'lead');
    expect(first.single.from, 'dev');
    expect(IdleNotification.tryParse(first.single.content).from, 'dev');

    // Idempotent until re-tasked: a second idle edge stays silent.
    expect(policy.onMemberIdle(view, 'dev'), isEmpty);

    // Re-tasking re-arms the ping.
    policy.noteInboundWork('dev');
    expect(policy.onMemberIdle(view, 'dev'), hasLength(1));
  });

  test('the leader never notifies itself', () {
    policy.noteInboundWork('lead');
    expect(policy.onMemberIdle(view, 'lead'), isEmpty);
  });

  test('no notification when there is no leader', () {
    final leaderless = _FakeView(
      {'dev': AgentNode.test(memberId: 'dev')},
      null,
    );
    policy.noteInboundWork('dev');
    expect(policy.onMemberIdle(leaderless, 'dev'), isEmpty);
    // Work stays pending (not consumed) so a leader joining later still gets it.
    final withLeader = _FakeView(
      {
        'dev': AgentNode.test(memberId: 'dev'),
        'lead': AgentNode.test(memberId: 'lead', isTeamLead: true),
      },
      'lead',
    );
    expect(policy.onMemberIdle(withLeader, 'dev'), hasLength(1));
  });
}
