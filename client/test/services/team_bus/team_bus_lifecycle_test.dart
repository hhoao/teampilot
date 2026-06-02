import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';

void main() {
  test('onMemberIdle with empty inbox rings coordination doorbell', () {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode.test(memberId: 'leader', state: MemberState.busy);
    bus.declareMember(node);

    bus.onMemberIdle('leader');

    expect(node.state, MemberState.busy);
    expect(launcher.woken.single.memberId, 'leader');
    expect(launcher.woken.single.notice, TeamBus.coordinationLoopNotice);
  });

  test('onMemberIdle skips wake while in wait_for_message', () async {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode.test(memberId: 'leader', state: MemberState.busy);
    bus.declareMember(node);

    final waiting = bus.receive('leader');
    await Future<void>.delayed(Duration.zero);
    bus.onMemberIdle('leader');

    expect(launcher.woken, isEmpty);
    node.inbox.deliver(
      TeamMessage(id: '1', from: 'w', to: 'leader', content: 'ping'),
    );
    final batch = await waiting;
    expect(batch, hasLength(1));
  });

  test('onMemberIdle skips declared members without a running PTY', () {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    bus.declareMember(AgentNode.test(memberId: 'leader', state: MemberState.declared));

    bus.onMemberIdle('leader');

    expect(launcher.woken, isEmpty);
  });

  test('markMemberRunning promotes declared to busy', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(memberId: 'leader', state: MemberState.declared));

    bus.markMemberRunning('leader');

    expect(bus.memberById('leader')!.state, MemberState.busy);
  });

  test('onMemberIdle debounces empty-inbox coordination doorbell', () {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode.test(memberId: 'leader', state: MemberState.busy);
    bus.declareMember(node);

    bus.onMemberIdle('leader');
    bus.onMemberIdle('leader');

    expect(launcher.woken, hasLength(1));
    expect(launcher.woken.single.notice, TeamBus.coordinationLoopNotice);
  });

  test('onMemberIdle with pending mail rings the doorbell and stays busy', () {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode.test(memberId: 'leader', state: MemberState.busy);
    bus.declareMember(node);
    node.inbox.deliver(TeamMessage(id: '1', from: 'w', to: 'leader', content: 'x'));

    bus.onMemberIdle('leader');

    expect(launcher.woken.single.memberId, 'leader');
    expect(node.state, MemberState.busy);
  });

  test('leave retires a member', () {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode.test(memberId: 'w', state: MemberState.busy);
    bus.declareMember(node);

    bus.leave('w');

    expect(node.state, MemberState.retired);
  });

  test('broadcast with materializeDeclared launches declared workers', () async {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final leader = AgentNode.test(memberId: 'team-lead', state: MemberState.busy);
    final worker = AgentNode.test(memberId: 'developer', state: MemberState.declared);
    bus.declareMember(leader);
    bus.declareMember(worker);

    await bus.broadcast(
      TeamMessage(id: '1', from: 'team-lead', to: '*', content: 'go'),
      materializeDeclared: true,
    );

    expect(worker.state, MemberState.busy);
    expect(launcher.materialized.single.memberId, 'developer');
    expect(launcher.materialized.single.bootstrap.content, 'go');
  });

  test('finishTask retires leader and broadcasts stand-down to live members', () async {
    final launcher = FakeMemberLauncher();
    var n = 0;
    final bus = TeamBus(launcher: launcher, idGenerator: () => 'id${n++}');
    final leader = AgentNode.test(memberId: 'leader', state: MemberState.busy);
    final w1 = AgentNode.test(memberId: 'w1', state: MemberState.busy);
    final w2 = AgentNode.test(memberId: 'w2', state: MemberState.idle);
    final w3 = AgentNode.test(memberId: 'w3', state: MemberState.declared);
    bus.declareMember(leader);
    bus.declareMember(w1);
    bus.declareMember(w2);
    bus.declareMember(w3);

    await bus.finishTask('leader', 'done');

    expect(leader.state, MemberState.retired);
    expect(w1.inbox.isEmpty, isFalse); // busy worker gets stand-down
    expect(w2.inbox.isEmpty, isFalse); // idle worker gets stand-down
    expect(w2.state, MemberState.busy); // idle worker woken
    expect(launcher.woken.map((w) => w.memberId), ['w2']);
    expect(w3.inbox.isEmpty, isTrue); // declared worker skipped
    expect(launcher.materialized, isEmpty); // never materializes a declared one
  });
}
