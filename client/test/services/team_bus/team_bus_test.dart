import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import 'support/fake_member_launcher.dart';

void main() {
  test('hasPendingDoorbell true only while doorbelled with unread mail', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    final node = AgentNode.test(
      memberId: 'worker',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.turnDoneReady,
    );
    bus.declareMember(node);

    // No mail, no doorbell → not pending.
    expect(bus.hasPendingDoorbell('worker'), isFalse);

    // Delivering mail rings the doorbell and leaves it unread → pending.
    bus.deliverUserCommand('worker', 'hello');
    expect(bus.hasPendingDoorbell('worker'), isTrue);

    // Drain via readMessages with markRead → no longer pending.
    await bus.readMessages(
      'worker',
      unreadOnly: true,
      markRead: true,
    );
    expect(node.inbox.isEmpty, isTrue);
    expect(bus.hasPendingDoorbell('worker'), isFalse);
  });

  test('markMemberDiscarded returns a running member to declared, inbox kept', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    final node = AgentNode.test(
      memberId: 'worker',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.turnDoneReady,
    );
    bus.declareMember(node);

    // Seed unread so we can assert the inbox survives the discard.
    bus.deliverUserCommand('worker', 'hello');
    expect(node.lifecycle, MemberLifecycle.running);
    expect(node.inbox.isEmpty, isFalse);

    bus.markMemberDiscarded('worker');

    expect(node.lifecycle, MemberLifecycle.declared);
    expect(node.activity, MemberActivity.mailQueued,
      reason: 'unread inbox must surface as mailQueued after discard');
    expect(node.inbox.isEmpty, isFalse,
      reason: 'inbox must survive discard for later re-materialize');
  });
}
