import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/persistence/in_memory_bus_message_store.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';

void main() {
  test('readMessages pages unread and mark_read removes from hot queue', () async {
    final store = InMemoryBusMessageStore();
    final bus = TeamBus(launcher: FakeMemberLauncher(), messageStore: store);
    bus.declareMember(AgentNode.test(memberId: 'leader', lifecycle: MemberLifecycle.running, activity: MemberActivity.active));

    for (var i = 0; i < 5; i++) {
      await store.append(
        'leader',
        TeamMessage(id: 'm$i', from: 'dev', to: 'leader', content: 'msg$i'),
      );
      bus.memberById('leader')!.inbox.deliver(
        TeamMessage(id: 'm$i', from: 'dev', to: 'leader', content: 'msg$i'),
      );
    }

    final p1 = await bus.readMessages('leader', limit: 2, markRead: true);
    expect(p1.messages.map((m) => m.id), ['m0', 'm1']);
    expect(p1.hasMore, isTrue);
    expect(p1.nextAfterId, 'm1');
    expect(await store.unreadCount('leader'), 3);
    expect(bus.memberById('leader')!.inbox.unreadCount, 3);

    final p2 = await bus.readMessages(
      'leader',
      afterId: p1.nextAfterId,
      limit: 10,
      markRead: false,
    );
    expect(p2.messages.map((m) => m.id), ['m2', 'm3', 'm4']);
    expect(p2.hasMore, isFalse);
  });

  test('receive marks persisted messages read', () async {
    final store = InMemoryBusMessageStore();
    final bus = TeamBus(launcher: FakeMemberLauncher(), messageStore: store);
    final node = AgentNode.test(memberId: 'leader', lifecycle: MemberLifecycle.running, activity: MemberActivity.active);
    bus.declareMember(node);

    await store.append(
      'leader',
      TeamMessage(id: '1', from: 'w', to: 'leader', content: 'hi'),
    );
    node.inbox.deliver(
      TeamMessage(id: '1', from: 'w', to: 'leader', content: 'hi'),
    );

    final batch = await bus.receive('leader');
    expect(batch, hasLength(1));
    expect(await store.unreadCount('leader'), 0);
  });

  test('rehydrateUnread restores cold unread into hot mailbox', () async {
    final store = InMemoryBusMessageStore();
    final bus = TeamBus(launcher: FakeMemberLauncher(), messageStore: store);
    bus.declareMember(AgentNode.test(memberId: 'leader'));

    await store.append(
      'leader',
      TeamMessage(id: 'a', from: 'w', to: 'leader', content: 'restored'),
    );

    await bus.rehydrateUnread();

    expect(bus.memberById('leader')!.inbox.unreadCount, 1);
    await bus.rehydrateUnread();
    expect(bus.memberById('leader')!.inbox.unreadCount, 1);
  });
}
