import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import 'support/fake_member_launcher.dart';

void main() {
  test('messagesSnapshot aggregates member inboxes sorted by time', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    ));
    bus.declareMember(AgentNode.test(
      memberId: 'worker',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    ));

    bus.deliverUserCommand('leader', 'to leader');
    bus.deliverUserCommand('worker', 'to worker');

    final feed = await bus.messagesSnapshot();
    expect(feed.length, 2);
    expect(feed.every((e) => e.from == TeamBus.userSenderId), isTrue);
    expect(feed.map((e) => e.content),
        containsAll(['to leader', 'to worker']));
    expect(feed.every((e) => e.isUnread), isTrue);
    // Sorted ascending by createdAt.
    expect(feed.first.createdAt <= feed.last.createdAt, isTrue);
  });

  test('messagesSnapshot is empty with no members', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    expect(await bus.messagesSnapshot(), isEmpty);
  });
}
