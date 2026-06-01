import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';

void main() {
  test('onMemberIdle with empty inbox goes idle without waking', () {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode(memberId: 'leader', state: MemberState.busy);
    bus.declareMember(node);

    bus.onMemberIdle('leader');

    expect(node.state, MemberState.idle);
    expect(launcher.woken, isEmpty);
  });

  test('onMemberIdle with pending mail rings the doorbell and stays busy', () {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode(memberId: 'leader', state: MemberState.busy);
    bus.declareMember(node);
    node.inbox.deliver(TeamMessage(id: '1', from: 'w', to: 'leader', content: 'x'));

    bus.onMemberIdle('leader');

    expect(launcher.woken.single.memberId, 'leader');
    expect(node.state, MemberState.busy);
  });

  test('leave retires a member', () {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode(memberId: 'w', state: MemberState.busy);
    bus.declareMember(node);

    bus.leave('w');

    expect(node.state, MemberState.retired);
  });
}
