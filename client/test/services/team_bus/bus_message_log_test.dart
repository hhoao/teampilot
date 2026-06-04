import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/cancellation.dart';
import 'package:teampilot/services/team_bus/persistence/bus_message_log.dart';
import 'package:teampilot/services/team_bus/persistence/in_memory_bus_message_log.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';

/// Persisted unread, read straight from the log (the single source of truth).
Future<int> _logUnread(BusMessageLog log, String member) async =>
    (await log.load(member)).where((r) => r.isUnread).length;

TeamMessage _m(String id) =>
    TeamMessage(id: id, from: 'w', to: 'leader', content: id);

AgentNode _runningLeader() => AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );

void main() {
  test('receivePending unblocks and clears park when cancelled', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.turnDoneReady,
    ));

    final cancel = CancellationToken();
    final pending = bus.receivePending('leader', cancel: cancel);
    await Future<void>.delayed(Duration.zero);
    expect(bus.isWaitingForMessage('leader'), isTrue);

    cancel.cancel();
    expect(await pending, isEmpty);
    expect(bus.isWaitingForMessage('leader'), isFalse,
        reason: 'cancel must release the park, not leak it');
  });

  test('readMessages browses unread pages without consuming', () async {
    final bus = TeamBus(
      launcher: FakeMemberLauncher(),
      messageLog: InMemoryBusMessageLog(),
    );
    final node = _runningLeader();
    bus.declareMember(node);
    for (var i = 0; i < 5; i++) {
      node.inbox.deliver(_m('m$i'));
    }

    final p1 = await bus.readMessages('leader', limit: 2);
    expect(p1.messages.map((m) => m.id), ['m0', 'm1']);
    expect(p1.hasMore, isTrue);
    expect(p1.nextAfterId, 'm1');
    expect(node.inbox.unreadCount, 5, reason: 'browse must not consume');

    final p2 = await bus.readMessages('leader', afterId: 'm1', limit: 10);
    expect(p2.messages.map((m) => m.id), ['m2', 'm3', 'm4']);
    expect(p2.hasMore, isFalse);
  });

  test('readMessages mark_read consumes and persists read', () async {
    final log = InMemoryBusMessageLog();
    final bus = TeamBus(launcher: FakeMemberLauncher(), messageLog: log);
    final node = _runningLeader();
    bus.declareMember(node);
    for (var i = 0; i < 3; i++) {
      node.inbox.deliver(_m('m$i'));
    }

    final page = await bus.readMessages('leader', limit: 2, markRead: true);
    expect(page.messages.map((m) => m.id), ['m0', 'm1']);
    expect(node.inbox.unreadCount, 1);
    expect(await _logUnread(log, 'leader'), 1, reason: 'read persisted to log');
  });

  test('receive marks delivered messages read in the log', () async {
    final log = InMemoryBusMessageLog();
    final bus = TeamBus(launcher: FakeMemberLauncher(), messageLog: log);
    final node = _runningLeader();
    bus.declareMember(node);
    node.inbox.deliver(_m('1'));

    final batch = await bus.receive('leader');
    expect(batch, hasLength(1));
    expect(await _logUnread(log, 'leader'), 0);
  });

  test('receivePending takes but leaves log unread until ack', () async {
    final log = InMemoryBusMessageLog();
    final bus = TeamBus(launcher: FakeMemberLauncher(), messageLog: log);
    final node = _runningLeader();
    bus.declareMember(node);
    node.inbox.deliver(_m('1'));

    final batch = await bus.receivePending('leader');
    expect(batch, hasLength(1));
    expect(node.inbox.unreadCount, 0); // taken from memory
    expect(await _logUnread(log, 'leader'), 1); // NOT read until confirmed

    await bus.acknowledgeDelivery('leader', ['1']);
    expect(await _logUnread(log, 'leader'), 0);
  });

  test('redeliver restores a taken-but-unconfirmed batch (no loss)', () async {
    final log = InMemoryBusMessageLog();
    final bus = TeamBus(launcher: FakeMemberLauncher(), messageLog: log);
    final node = _runningLeader();
    bus.declareMember(node);
    node.inbox.deliver(_m('1'));

    final batch = await bus.receivePending('leader');
    expect(node.inbox.unreadCount, 0);

    bus.redeliver('leader', batch); // SSE write failed before confirm
    expect(node.inbox.unreadCount, 1);
    expect(await _logUnread(log, 'leader'), 1);

    expect((await bus.receivePending('leader')).map((m) => m.id), ['1']);
  });

  test('rehydrateUnread rebuilds the unread set from the log (idempotent)',
      () async {
    final log = InMemoryBusMessageLog();
    await log.appendMessage(
      'leader',
      0,
      _m('a'),
      0,
    );
    final bus = TeamBus(launcher: FakeMemberLauncher(), messageLog: log);
    bus.declareMember(AgentNode.test(memberId: 'leader'));

    await bus.rehydrateUnread();
    expect(bus.memberById('leader')!.inbox.unreadCount, 1);
    await bus.rehydrateUnread();
    expect(bus.memberById('leader')!.inbox.unreadCount, 1);
  });
}
