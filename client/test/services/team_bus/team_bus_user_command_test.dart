import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';

void main() {
  test('isWaitingForMessage tracks receive lifecycle', () {
    fakeAsync((async) {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      bus.declareMember(AgentNode.test(memberId: 'leader', lifecycle: MemberLifecycle.running, activity: MemberActivity.active));

      expect(bus.isWaitingForMessage('leader'), isFalse);

      List<TeamMessage>? batch;
      bus.receive('leader').then((b) => batch = b);
      async.flushMicrotasks();
      expect(bus.isWaitingForMessage('leader'), isTrue);

      bus.deliverUserCommand('leader', 'next task');
      async.elapse(const Duration(milliseconds: 50));
      expect(batch!.single.content, 'next task');
      expect(batch!.single.from, TeamBus.userSenderId);
      expect(bus.isWaitingForMessage('leader'), isFalse);
    });
  });

  test('deliverUserCommand enqueues for later wait when not parked', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    final node = AgentNode.test(memberId: 'leader', lifecycle: MemberLifecycle.running, activity: MemberActivity.active);
    bus.declareMember(node);

    bus.deliverUserCommand('leader', 'hello');
    expect(node.inbox.isEmpty, isFalse);

    final batch = await node.inbox.waitAndTake(timeout: const Duration(seconds: 1));
    expect(batch.single.from, TeamBus.userSenderId);
    expect(batch.single.content, 'hello');
  });

  test('deliverUserCommand returns id; isUnread flips when taken', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    final node = AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );
    bus.declareMember(node);

    final id = bus.deliverUserCommand('leader', 'hello');
    expect(id, isNotEmpty);
    expect(bus.isUnread('leader', id), isTrue);
    expect(bus.isUnread('leader', 'nope'), isFalse);
    expect(bus.isUnread('ghost', id), isFalse);

    await node.inbox.waitAndTake(timeout: const Duration(seconds: 1));
    expect(bus.isUnread('leader', id), isFalse);
  });

  test('deliverUserCommand returns empty id for blank line', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    ));
    expect(bus.deliverUserCommand('leader', '   '), isEmpty);
  });
}
