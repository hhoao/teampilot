import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';

void main() {
  group('MemberActivity turn-done family', () {
    test('claudeIsActive is true only for active', () {
      final busWait = AgentNode.test(
        memberId: 'w',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.turnDoneBusWait,
      );
      expect(busWait.claudeIsActive, isFalse);
      expect(busWait.waitingForMessage, isTrue);
      expect(busWait.busPhaseLabel, 'turn_done · bus_wait');

      final mailQueued = AgentNode.test(
        memberId: 'w',
        lifecycle: MemberLifecycle.declared,
        activity: MemberActivity.mailQueued,
      );
      expect(mailQueued.claudeIsActive, isNull);
      expect(mailQueued.waitingForMessage, isFalse);
      expect(mailQueued.busPhaseLabel, 'no_pty · mail_queued');
    });

    test('busPhaseLabel + waitingForMessage reflect activity', () {
      final ready = AgentNode.test(
        memberId: 'w',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.turnDoneReady,
      );
      expect(ready.busPhaseLabel, 'turn_done · ready');
      expect(ready.waitingForMessage, isFalse);

      final waiting = AgentNode.test(
        memberId: 'w',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.turnDoneBusWait,
      );
      expect(waiting.waitingForMessage, isTrue);
    });
  });
}
