import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mailbox_delivery.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';

void main() {
  group('TeamBus mailbox delivery (Phase 1)', () {
    test('markMailDeliveryFailed stops pendingDoorbellNoticeFor', () {
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
      expect(bus.pendingDoorbellNoticeFor('worker'), isNull);
    });

    test('reengageIdleWorkers skips failed delivery', () {
      final launcher = FakeMemberLauncher();
      final bus = TeamBus(launcher: launcher);
      final node = AgentNode.test(
        memberId: 'worker',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.turnDoneReady,
      );
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

      expect(launcher.woken, isEmpty);
      expect(launcher.retried, isEmpty);
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

    test('shouldDeferPtyIdleEnd is false when delivery failed', () {
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

      expect(bus.shouldDeferPtyIdleEnd('worker'), isFalse);
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
