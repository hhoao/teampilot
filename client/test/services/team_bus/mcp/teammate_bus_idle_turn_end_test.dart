import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_http_delegate.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import '../support/fake_member_launcher.dart';

void main() {
  test('endTurnForIdle ends the bus turn for a push (cursor) member', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(
      memberId: 'worker',
      cli: 'cursor',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active, // in turn
    ));
    final handler = TeammateBusMcpHandler(bus: bus, forceWaitBeforeStop: false);
    final delegate = TeammateBusMcpHttpDelegate(handler: handler);

    // in-turn before idle
    expect(bus.isMemberInTurn('worker'), isTrue);

    // Simulate the CLI stop-hook POST /idle.
    delegate.endTurnForIdle('worker');

    // Turn ended → member no longer in turn.
    expect(bus.isMemberInTurn('worker'), isFalse);
  });
}
