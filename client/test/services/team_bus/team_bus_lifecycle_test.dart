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

  test('markTurnStarted moves running-at-prompt member to active (working)', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(
      AgentNode.test(
        memberId: 'leader',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.turnDoneReady,
      ),
    );
    expect(bus.isMemberInTurn('leader'), isFalse);

    bus.markTurnStarted('leader');

    expect(bus.memberById('leader')!.activity, MemberActivity.active);
    expect(bus.isMemberInTurn('leader'), isTrue);
  });

  test('markTurnStarted is a no-op for a parked (wait_for_message) member', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    final node = AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );
    bus.declareMember(node);
    bus.receive('leader'); // enters wait_for_message → turnDoneBusWait
    expect(bus.isWaitingForMessage('leader'), isTrue);

    bus.markTurnStarted('leader');

    // Parked is handled by the wait/mail wake path, not commandeered here.
    expect(bus.isWaitingForMessage('leader'), isTrue);
    expect(bus.isMemberInTurn('leader'), isFalse);
  });

  test('markTurnStarted is a no-op for a declared (no PTY) member', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(
      AgentNode.test(memberId: 'leader', lifecycle: MemberLifecycle.declared),
    );

    bus.markTurnStarted('leader');

    expect(bus.memberById('leader')!.lifecycle, MemberLifecycle.declared);
    expect(bus.isMemberInTurn('leader'), isFalse);
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
    'repeated idle edges with one unread ring the doorbell exactly once',
    () {
      // A single turn-end is reported by BOTH the CLI Stop-hook /idle POST and
      // the 1s terminal activity watcher (and the injected notice itself jolts
      // activity). Without doorbell idempotency each onMemberIdle re-injected
      // "[teammate-bus] You have unread teammate messages" → the user saw it
      // twice. It must ring once per unread episode.
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
      bus.onMemberIdle('leader');
      bus.onMemberIdle('leader');

      expect(launcher.woken, hasLength(1));
    },
  );

  test(
    'doorbell re-arms after the member consumes via wait_for_message',
    () async {
      final launcher = FakeMemberLauncher();
      final bus = TeamBus(launcher: launcher);
      final node = AgentNode.test(
        memberId: 'leader',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      );
      bus.declareMember(node);
      node.inbox.deliver(
        TeamMessage(id: '1', from: 'w', to: 'leader', content: 'first'),
      );

      // First unread episode: rings once even across duplicate idle reports.
      bus.onMemberIdle('leader');
      bus.onMemberIdle('leader');
      expect(launcher.woken, hasLength(1));

      // Member responds to the nudge and drains the mailbox.
      final batch = await bus.receive('leader');
      expect(batch, hasLength(1));

      // A brand-new message after reading must be able to ring again.
      node.inbox.deliver(
        TeamMessage(id: '2', from: 'w', to: 'leader', content: 'second'),
      );
      bus.onMemberIdle('leader');
      expect(launcher.woken, hasLength(2));
    },
  );

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
