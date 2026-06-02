import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';

void main() {
  test(
    'onMemberIdle with empty inbox rings coordination doorbell when PTY running',
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

      expect(node.activity, MemberActivity.active);
      expect(launcher.woken.single.memberId, 'leader');
      expect(launcher.woken.single.notice, TeamBus.coordinationLoopNotice);
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
    'onMemberIdle debounces empty-inbox coordination doorbell when PTY running',
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

      expect(launcher.woken, hasLength(1));
      expect(launcher.woken.single.notice, TeamBus.coordinationLoopNotice);
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

  test('leave retires a member', () {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode.test(
      memberId: 'w',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );
    bus.declareMember(node);

    bus.leave('w');

    expect(node.lifecycle, MemberLifecycle.retired);
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

  test(
    'finishTask retires leader and broadcasts stand-down to live members',
    () async {
      final launcher = FakeMemberLauncher();
      var n = 0;
      final bus = TeamBus(launcher: launcher, idGenerator: () => 'id${n++}');
      final leader = AgentNode.test(
        memberId: 'leader',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      );
      final w1 = AgentNode.test(
        memberId: 'w1',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      );
      final w2 = AgentNode.test(
        memberId: 'w2',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.turnDoneReady,
      );
      final w3 = AgentNode.test(
        memberId: 'w3',
        lifecycle: MemberLifecycle.declared,
      );
      bus.declareMember(leader);
      bus.declareMember(w1);
      bus.declareMember(w2);
      bus.declareMember(w3);

      await bus.finishTask('leader', 'done');

      expect(leader.lifecycle, MemberLifecycle.retired);
      expect(w1.inbox.isEmpty, isFalse); // busy worker gets stand-down
      expect(w2.inbox.isEmpty, isFalse); // idle worker gets stand-down
      expect(w2.activity, MemberActivity.active); // idle worker woken
      expect(launcher.woken.map((w) => w.memberId), ['w2']);
      expect(w3.inbox.isEmpty, isTrue); // declared worker skipped
      expect(
        launcher.materialized,
        isEmpty,
      ); // never materializes a declared one
    },
  );
}
