import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';

void main() {
  test(
    'onMemberIdle with empty inbox does not ring doorbell when PTY running',
    () {
      final launcher = FakeMemberLauncher();
      final bus = TeamBus(launcher: launcher);
      final node = AgentNode.test(
        memberId: 'leader',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      );
      bus.declareMember(node);

      bus.onMemberIdle('leader');

      expect(node.activity, MemberActivity.turnDoneReady);
      expect(launcher.woken, isEmpty);
    },
  );

  test('onMemberIdle skips wake while in wait_for_message', () async {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );
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
    final node = AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.declared,
    );
    bus.declareMember(node);
    node.inbox.deliver(
      TeamMessage(id: '1', from: 'w', to: 'leader', content: 'queued'),
    );

    bus.onMemberIdle('leader');

    expect(node.lifecycle, MemberLifecycle.declared);
    expect(launcher.woken, isEmpty);
  });

  test('markMemberRunning promotes declared to running at prompt', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(
      AgentNode.test(memberId: 'leader', lifecycle: MemberLifecycle.declared),
    );

    bus.markMemberRunning('leader');

    expect(bus.memberById('leader')!.lifecycle, MemberLifecycle.running);
    expect(bus.memberById('leader')!.activity, MemberActivity.turnDoneReady);
  });

  test(
    'onMemberIdle with empty inbox stays quiet across repeated idle edges',
    () {
      final launcher = FakeMemberLauncher();
      final bus = TeamBus(launcher: launcher);
      final node = AgentNode.test(
        memberId: 'leader',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      );
      bus.declareMember(node);

      bus.onMemberIdle('leader');
      bus.onMemberIdle('leader');

      expect(node.activity, MemberActivity.turnDoneReady);
      expect(launcher.woken, isEmpty);
    },
  );

  test('onMemberIdle with pending mail rings the doorbell and stays busy', () {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );
    bus.declareMember(node);
    node.inbox.deliver(
      TeamMessage(id: '1', from: 'w', to: 'leader', content: 'x'),
    );

    bus.onMemberIdle('leader');

    expect(launcher.woken.single.memberId, 'leader');
    expect(node.activity, MemberActivity.active);
  });

  test(
    'broadcast with materializeDeclared launches declared workers',
    () async {
      final launcher = FakeMemberLauncher();
      final bus = TeamBus(launcher: launcher);
      final leader = AgentNode.test(
        memberId: 'team-lead',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      );
      final worker = AgentNode.test(
        memberId: 'developer',
        lifecycle: MemberLifecycle.declared,
      );
      bus.declareMember(leader);
      bus.declareMember(worker);

      await bus.broadcast(
        TeamMessage(id: '1', from: 'team-lead', to: '*', content: 'go'),
        materializeDeclared: true,
      );

      expect(worker.lifecycle, MemberLifecycle.running);
      expect(launcher.materialized.single.memberId, 'developer');
      expect(launcher.materialized.single.bootstrap.content, 'go');
    },
  );

}
