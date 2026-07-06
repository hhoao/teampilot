import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';
import 'package:teampilot/services/terminal/pty_automation_delivery_guard.dart';

import '../team_bus/support/fake_member_launcher.dart';

void main() {
  group('PtyAutomationDeliveryGuard', () {
    test('skips when worker is parked in wait_for_message', () {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      bus.declareMember(
        AgentNode.test(
          memberId: 'worker',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.turnDoneBusWait,
        ),
      );

      expect(
        PtyAutomationDeliveryGuard.shouldSkipRetry(bus: bus, memberId: 'worker'),
        isTrue,
      );
    });

    test('skips when inbox is empty and no task doorbell is owed', () {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      bus.declareMember(
        AgentNode.test(
          memberId: 'worker',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.turnDoneReady,
        ),
      );

      expect(
        PtyAutomationDeliveryGuard.shouldSkipRetry(bus: bus, memberId: 'worker'),
        isTrue,
      );
    });

    test('does not skip when unread mail still owes a doorbell', () {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      final node = AgentNode.test(
        memberId: 'worker',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.turnDoneReady,
      );
      bus.declareMember(node);
      node.inbox.deliver(
        TeamMessage(id: 'm1', from: 'lead', to: 'worker', content: 'ping'),
      );

      expect(
        PtyAutomationDeliveryGuard.shouldSkipRetry(bus: bus, memberId: 'worker'),
        isFalse,
      );
      expect(bus.pendingDoorbellNoticeFor('worker'), isNotNull);
    });

    test('does not skip when operator turn is latched', () {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      bus.declareMember(
        AgentNode.test(
          memberId: 'worker',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.turnDoneBusWait,
        ),
      );

      expect(
        PtyAutomationDeliveryGuard.shouldSkipRetry(
          bus: bus,
          memberId: 'worker',
          operatorTurnActive: true,
        ),
        isFalse,
      );
    });

    test('does not skip when automation retry is still queued', () {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      bus.declareMember(
        AgentNode.test(
          memberId: 'worker',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.turnDoneReady,
        ),
      );

      expect(
        PtyAutomationDeliveryGuard.shouldSkipRetry(
          bus: bus,
          memberId: 'worker',
          pendingAutomationRetry: true,
        ),
        isFalse,
      );
    });

    test('null bus never skips', () {
      expect(
        PtyAutomationDeliveryGuard.shouldSkipRetry(bus: null, memberId: 'worker'),
        isFalse,
      );
    });
  });
}
