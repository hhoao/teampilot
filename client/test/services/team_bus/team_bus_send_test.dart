import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';
import 'package:teampilot/services/team_bus/teammate_roster_profile.dart';

import 'support/fake_member_launcher.dart';

void main() {
  test('receive parks until a message is delivered to the member inbox', () {
    fakeAsync((async) {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      final node = AgentNode.test(
        memberId: 'leader',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      );
      bus.declareMember(node);

      List<TeamMessage>? got;
      bus
          .receive('leader', timeout: const Duration(seconds: 30))
          .then((b) => got = b);
      async.flushMicrotasks();
      expect(got, isNull);

      node.inbox.deliver(
        TeamMessage(id: '1', from: 'w', to: 'leader', content: 'hi'),
      );
      async.elapse(const Duration(milliseconds: 50));
      expect(got!.single.content, 'hi');
    });
  });

  test('receive on unknown member returns an empty batch', () {
    fakeAsync((async) {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      List<TeamMessage>? got;
      bus
          .receive('ghost', timeout: const Duration(seconds: 1))
          .then((b) => got = b);
      async.flushMicrotasks();
      expect(got, isEmpty);
    });
  });

  test(
    'send to a declared member materializes and enqueues the message',
    () async {
      final launcher = FakeMemberLauncher();
      final bus = TeamBus(launcher: launcher);
      final worker = AgentNode.test(memberId: 'worker');
      bus.declareMember(worker);

      await bus.send(
        TeamMessage(id: '1', from: 'leader', to: 'worker', content: 'do X'),
      );

      expect(launcher.materialized.single.memberId, 'worker');
      expect(launcher.materialized.single.bootstrap.content, 'do X');
      expect(worker.lifecycle, MemberLifecycle.running);
      expect(worker.inbox.isEmpty, isFalse);
      expect(launcher.woken.single.memberId, 'worker');
      expect(launcher.woken.single.notice, TeamBus.doorbellNotice);
      final batch = await worker.inbox.waitAndTake(
        timeout: const Duration(seconds: 1),
      );
      expect(batch.single.content, 'do X');
    },
  );

  test('send to an active member only enqueues', () async {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );
    bus.declareMember(node);

    await bus.send(TeamMessage(id: '1', from: 'w', to: 'leader', content: 'x'));

    expect(node.inbox.isEmpty, isFalse);
    expect(launcher.woken, isEmpty);
    expect(launcher.materialized, isEmpty);
  });

  test('send to a member in wait_for_message only enqueues', () async {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.turnDoneReady,
    );
    bus.declareMember(node);

    final waiting = bus.receive('leader');
    await Future<void>.delayed(Duration.zero);
    expect(node.waitingForMessage, isTrue);
    expect(node.claudeIsActive, isFalse);

    await bus.send(
      TeamMessage(id: '1', from: 'w', to: 'leader', content: 'queued'),
    );

    expect(launcher.woken, isEmpty);
    final batch = await waiting;
    expect(batch.single.content, 'queued');
  });

  test('send to an idle member enqueues and rings the doorbell', () async {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.turnDoneReady,
    );
    bus.declareMember(node);

    await bus.send(TeamMessage(id: '1', from: 'w', to: 'leader', content: 'r'));

    expect(node.inbox.isEmpty, isFalse);
    expect(launcher.woken.single.memberId, 'leader');
    expect(launcher.woken.single.notice, TeamBus.doorbellNotice);
    expect(node.activity, MemberActivity.active);
  });

  test('send drops over-hop and unknown targets', () async {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher, maxHop: 3);
    final busy = AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );
    bus.declareMember(busy);

    final overHop = await bus.send(
      TeamMessage(id: '1', from: 'x', to: 'leader', content: 'a', hop: 3),
    );
    expect(busy.inbox.isEmpty, isTrue); // dropped: hop >= maxHop
    expect(overHop.delivered, isFalse);
    expect(overHop.reason, contains('over-hop'));

    final unknown = await bus.send(
      TeamMessage(id: '2', from: 'x', to: 'ghost', content: 'a'),
    );
    expect(launcher.materialized, isEmpty); // unknown target
    expect(unknown.delivered, isFalse);
    expect(unknown.reason, 'unknown-member');
  });

  test('send resolves agentId addresses to member id', () async {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher)
      ..installSessionContext(
        const TeamSessionContext(
          cliTeamName: 'testmixed-23',
          teamId: 'testmixed',
          teamName: 'TestMixed',
        ),
      );
    final developer = AgentNode(
      profile: TeammateRosterProfile.fromMember(
        member: const TeamMemberConfig(id: 'developer', name: 'Dev'),
        team: const TeamConfig(id: 'testmixed', name: 'TestMixed'),
        cliTeamName: 'testmixed-23',
        cwd: '/tmp',
      ),
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );
    bus.declareMember(developer);

    final outcome = await bus.send(
      TeamMessage(
        id: '1',
        from: 'team-lead',
        to: 'developer@testmixed-23',
        content: 'hi',
      ),
    );

    expect(outcome.delivered, isTrue);
    expect(outcome.memberId, 'developer');
    expect(developer.inbox.isEmpty, isFalse);
    final batch = await developer.inbox.waitAndTake(
      timeout: const Duration(seconds: 1),
    );
    expect(batch.single.to, 'developer');
    expect(batch.single.content, 'hi');
  });
}
