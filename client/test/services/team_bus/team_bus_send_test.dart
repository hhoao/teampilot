import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';

void main() {
  test('receive parks until a message is delivered to the member inbox', () {
    fakeAsync((async) {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      final node = AgentNode(memberId: 'leader', state: MemberState.busy);
      bus.declareMember(node);

      List<TeamMessage>? got;
      bus.receive('leader', timeout: const Duration(seconds: 30)).then((b) => got = b);
      async.flushMicrotasks();
      expect(got, isNull);

      node.inbox.deliver(TeamMessage(id: '1', from: 'w', to: 'leader', content: 'hi'));
      async.elapse(const Duration(milliseconds: 50));
      expect(got!.single.content, 'hi');
    });
  });

  test('receive on unknown member returns an empty batch', () {
    fakeAsync((async) {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      List<TeamMessage>? got;
      bus.receive('ghost', timeout: const Duration(seconds: 1)).then((b) => got = b);
      async.flushMicrotasks();
      expect(got, isEmpty);
    });
  });

  test('send to a declared member materializes it with the message', () async {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    bus.declareMember(AgentNode(memberId: 'worker'));

    await bus.send(
      TeamMessage(id: '1', from: 'leader', to: 'worker', content: 'do X'),
    );

    expect(launcher.materialized.single.memberId, 'worker');
    expect(launcher.materialized.single.bootstrap.content, 'do X');
    expect(bus.memberById('worker')!.state, MemberState.busy);
    expect(launcher.woken, isEmpty);
  });

  test('send to a busy member only enqueues', () async {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode(memberId: 'leader', state: MemberState.busy);
    bus.declareMember(node);

    await bus.send(TeamMessage(id: '1', from: 'w', to: 'leader', content: 'x'));

    expect(node.inbox.isEmpty, isFalse);
    expect(launcher.woken, isEmpty);
    expect(launcher.materialized, isEmpty);
  });

  test('send to an idle member enqueues and rings the doorbell', () async {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode(memberId: 'leader', state: MemberState.idle);
    bus.declareMember(node);

    await bus.send(TeamMessage(id: '1', from: 'w', to: 'leader', content: 'r'));

    expect(node.inbox.isEmpty, isFalse);
    expect(launcher.woken.single.memberId, 'leader');
    expect(launcher.woken.single.notice, TeamBus.doorbellNotice);
    expect(node.state, MemberState.busy);
  });

  test('send drops over-hop, unknown, and retired targets', () async {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher, maxHop: 3);
    final busy = AgentNode(memberId: 'leader', state: MemberState.busy);
    final retired = AgentNode(memberId: 'old', state: MemberState.retired);
    bus.declareMember(busy);
    bus.declareMember(retired);

    await bus.send(
      TeamMessage(id: '1', from: 'x', to: 'leader', content: 'a', hop: 3),
    );
    expect(busy.inbox.isEmpty, isTrue); // dropped: hop >= maxHop

    await bus.send(TeamMessage(id: '2', from: 'x', to: 'ghost', content: 'a'));
    expect(launcher.materialized, isEmpty); // unknown target

    await bus.send(TeamMessage(id: '3', from: 'x', to: 'old', content: 'a'));
    expect(retired.inbox.isEmpty, isTrue); // dropped: retired
  });
}
