import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mailbox_delivery.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';

void main() {
  group('TeamBus mailbox delivery (Phase 1)', () {
    test('failed delivery still owes doorbell while unread', () {
      final launcher = FakeMemberLauncher();
      final bus = TeamBus(launcher: launcher);
      final node = AgentNode.test(
        memberId: 'worker',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.turnDoneReady,
      )..doorbelled = true;
      bus.declareMember(node);
      node.inbox.deliver(
        TeamMessage(
          id: 'm1',
          from: 'lead',
          to: 'worker',
          content: 'ping',
        ),
      );

      bus.markMailDeliveryFailed(
        'worker',
        error: MailboxDeliveryError.crStuck,
      );

      expect(node.deliveryPhase, MailboxDeliveryPhase.failed);
      // failed 非终态:未读即欠门铃
      expect(bus.pendingDoorbellNoticeFor('worker'), TeamBus.doorbellNotice);
    });

    test('reengageIdleWorkers retries failed delivery (never terminal)', () {
      final launcher = FakeMemberLauncher();
      final bus = TeamBus(launcher: launcher);
      final node = AgentNode.test(
        memberId: 'worker',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.turnDoneReady,
      )..doorbelled = true;
      bus.declareMember(node);
      node.inbox.deliver(
        TeamMessage(
          id: 'm1',
          from: 'lead',
          to: 'worker',
          content: 'ping',
        ),
      );
      bus.markMailDeliveryFailed(
        'worker',
        error: MailboxDeliveryError.crStuck,
      );

      bus.reengageIdleWorkers();

      // 已响过门铃且投递失败 → retryDelivery,而非直接 wake
      expect(launcher.retried, isNotEmpty);
      expect(launcher.retried.first.memberId, 'worker');
    });

    test('parked member with unread owes no doorbell', () {
      final launcher = FakeMemberLauncher();
      final bus = TeamBus(launcher: launcher);
      final node = AgentNode.test(
        memberId: 'worker',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.turnDoneBusWait,
      );
      bus.declareMember(node);
      node.inbox.deliver(
        TeamMessage(id: 'm1', from: 'lead', to: 'worker', content: 'ping'),
      );

      expect(bus.pendingDoorbellNoticeFor('worker'), isNull);
    });

    test('new mail clears failed phase for another notify round', () async {
      final launcher = FakeMemberLauncher();
      final bus = TeamBus(launcher: launcher);
      bus.declareMember(
        AgentNode.test(
          memberId: 'worker',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.turnDoneReady,
        ),
      );
      bus.markMailDeliveryFailed(
        'worker',
        error: MailboxDeliveryError.crStuck,
      );

      await bus.send(
        TeamMessage(
          id: 'm2',
          from: 'lead',
          to: 'worker',
          content: 'again',
        ),
      );

      final node = bus.memberById('worker')!;
      expect(node.deliveryPhase, isNot(MailboxDeliveryPhase.failed));
      expect(bus.pendingDoorbellNoticeFor('worker'), isNotNull);
    });

    test('shouldDeferPtyIdleEnd is true when delivery failed (doorbell still owed)', () {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      final node = AgentNode.test(
        memberId: 'worker',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      )..doorbelled = true;
      bus.declareMember(node);
      node.inbox.deliver(
        TeamMessage(id: 'm1', from: 'lead', to: 'worker', content: 'ping'),
      );
      bus.markMailDeliveryFailed(
        'worker',
        error: MailboxDeliveryError.crStuck,
      );

      // failed 非终态:门铃仍欠着,PTY 安静不该提前结束回合
      expect(bus.shouldDeferPtyIdleEnd('worker'), isTrue);
    });

    test('noteMailDeliverySubmitted marks agent in-turn', () {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      final node = AgentNode.test(
        memberId: 'worker',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.turnDoneReady,
      );
      bus.declareMember(node);

      bus.noteMailDeliverySubmitted('worker');

      expect(node.activity, MemberActivity.active);
      expect(bus.isMemberInTurn('worker'), isTrue);
    });
  });
}
