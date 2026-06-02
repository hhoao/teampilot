import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/idle_notification.dart';
import 'package:teampilot/services/team_bus/persistence/in_memory_bus_message_store.dart';
import 'package:teampilot/services/team_bus/teammate_roster_profile.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import 'support/fake_member_launcher.dart';

void main() {
  test('IdleNotification round-trips JSON', () {
    final n = IdleNotification.fromWorker(
      memberId: 'developer',
      displayName: 'Developer',
      summary: 'done step 1',
    );
    final parsed = IdleNotification.tryParse(n.encode());
    expect(parsed.from, 'developer');
    expect(parsed.displayName, 'Developer');
    expect(parsed.idleReason, IdleReason.available);
    expect(parsed.summary, 'done step 1');
    expect(parsed.formatForLeader(), contains('IDLE NOTIFICATION'));
  });

  test('onMemberIdle delivers idle_notification to team-lead mailbox', () {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher, messageStore: InMemoryBusMessageStore());
    bus
      ..declareMember(
        AgentNode(
          profile: TeammateRosterProfile.minimal(
            'team-lead',
            displayName: 'Lead',
            isTeamLead: true,
          ),
          lifecycle: MemberLifecycle.running, activity: MemberActivity.active,
        ),
      )
      ..declareMember(
        AgentNode(
          profile: TeammateRosterProfile.minimal('developer', displayName: 'Dev'),
          lifecycle: MemberLifecycle.running, activity: MemberActivity.active,
        ),
      );

    bus.deliverUserCommand('developer', 'do the work'); // dispatch real work
    bus.onMemberIdle('developer');

    final leader = bus.memberById('team-lead')!;
    expect(leader.inbox.isEmpty, isFalse);
    final raw = leader.inbox.peekAll().single.content;
    final idle = IdleNotification.tryParse(raw);
    expect(idle.from, 'developer');
    expect(launcher.woken.any((w) => w.memberId == 'team-lead'), isTrue);
  });

  test('onMemberIdle does not notify leader when team-lead goes idle', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(
      AgentNode(
        profile: TeammateRosterProfile.minimal('team-lead', isTeamLead: true),
        lifecycle: MemberLifecycle.running, activity: MemberActivity.active,
      ),
    );

    bus.onMemberIdle('team-lead');

    expect(bus.memberById('team-lead')!.inbox.isEmpty, isTrue);
  });

  test('leader is notified once per dispatched batch; re-tasking re-arms', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus
      ..declareMember(
        AgentNode(
          profile: TeammateRosterProfile.minimal('team-lead', isTeamLead: true),
          lifecycle: MemberLifecycle.running, activity: MemberActivity.active,
        ),
      )
      ..declareMember(
        AgentNode(
          profile: const TeammateRosterProfile(memberId: 'developer'),
          lifecycle: MemberLifecycle.running, activity: MemberActivity.active,
        ),
      );
    final leader = bus.memberById('team-lead')!;

    // One dispatched batch → repeated idle edges report exactly once.
    bus.deliverUserCommand('developer', 'task one');
    bus.onMemberIdle('developer');
    bus.onMemberIdle('developer');
    expect(leader.inbox.unreadCount, 1);

    // A fresh task re-arms the report for the next idle.
    bus.deliverUserCommand('developer', 'task two');
    bus.onMemberIdle('developer');
    expect(leader.inbox.unreadCount, 2);
  });

  test('idle of a never-dispatched worker does not notify the leader', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus
      ..declareMember(
        AgentNode(
          profile: TeammateRosterProfile.minimal('team-lead', isTeamLead: true),
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.active,
        ),
      )
      ..declareMember(
        AgentNode(
          profile: TeammateRosterProfile.minimal('developer'),
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.active,
        ),
      );

    // Worker just booted and went idle without ever receiving a task.
    bus.onMemberIdle('developer');

    expect(bus.memberById('team-lead')!.inbox.isEmpty, isTrue);
  });
}
