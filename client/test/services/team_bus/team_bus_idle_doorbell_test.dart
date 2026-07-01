import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/idle_notification.dart';
import 'package:teampilot/services/team_bus/teammate_roster_profile.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';

void main() {
  TeamBus buildBus(FakeMemberLauncher launcher, {bool reportsViaReceiveWork = true}) {
    final bus = TeamBus(
      launcher: launcher,
      reportsIdleViaReceiveWork: (_) => reportsViaReceiveWork,
    );
    bus
      ..declareMember(
        AgentNode(
          profile: TeammateRosterProfile.minimal(
            'lead',
            displayName: 'Lead',
            isTeamLead: true,
          ),
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.active,
        ),
      )
      ..declareMember(
        AgentNode(
          profile: TeammateRosterProfile.minimal('worker', displayName: 'Worker'),
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.active,
        ),
      );
    return bus;
  }

  test(
    'receiveWork idle path skips onMemberIdle coordination when forceWait',
    () {
      fakeAsync((async) {
        final launcher = FakeMemberLauncher();
        final bus = buildBus(launcher);
        bus.deliverUserCommand('worker', 'do work');

        bus.onMemberIdle('worker');
        expect(bus.memberById('lead')!.inbox.isEmpty, isTrue);

        bus.receiveWork('worker');
        async.flushMicrotasks();

        unawaited(bus.receiveWork('worker'));
        async.flushMicrotasks();

        final leader = bus.memberById('lead')!;
        expect(leader.inbox.unreadCount, 1);
        expect(
          IdleNotification.tryParse(leader.inbox.peekAll().single.content).from,
          'worker',
        );
        expect(launcher.woken.where((w) => w.memberId == 'lead'), isEmpty);
      });
    },
  );

  test(
    'idle announce to parked leader does not doorbell',
    () {
      fakeAsync((async) {
        final launcher = FakeMemberLauncher();
        final bus = buildBus(launcher);
        bus.deliverUserCommand('worker', 'do work');
        bus.receiveWork('worker');
        async.flushMicrotasks();

        unawaited(bus.receiveWork('lead'));
        async.flushMicrotasks();
        expect(bus.isWaitingForMessage('lead'), isTrue);

        unawaited(bus.receiveWork('worker'));
        async.flushMicrotasks();

        expect(launcher.woken.where((w) => w.memberId == 'lead'), isEmpty);
        expect(bus.memberById('lead')!.inbox.unreadCount, 1);
      });
    },
  );

  test(
    'worker send then idle: parked leader gets mail via waiter without doorbell',
    () {
      fakeAsync((async) {
        final launcher = FakeMemberLauncher();
        final bus = buildBus(launcher);

        unawaited(bus.receiveWork('lead'));
        async.flushMicrotasks();
        expect(bus.isWaitingForMessage('lead'), isTrue);

        bus.send(
          TeamMessage(id: '1', from: 'worker', to: 'lead', content: 'done'),
        );
        async.flushMicrotasks();
        expect(launcher.woken.where((w) => w.memberId == 'lead'), isEmpty);

        bus.deliverUserCommand('worker', 'follow-up');
        unawaited(bus.receiveWork('worker'));
        async.flushMicrotasks();

        expect(launcher.woken.where((w) => w.memberId == 'lead'), isEmpty);
      });
    },
  );

  test(
    'cursor-style onMemberIdle still doorbells leader at prompt',
    () {
      final launcher = FakeMemberLauncher();
      final bus = buildBus(launcher, reportsViaReceiveWork: false);
      bus.deliverUserCommand('worker', 'do work');
      bus.onMemberIdle('worker');

      expect(bus.memberById('lead')!.inbox.unreadCount, 1);
      expect(
        launcher.woken.where((w) => w.memberId == 'lead').single.memberId,
        'lead',
      );
    },
  );
}
