import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import '../../services/team_bus/support/fake_member_launcher.dart';
import 'integration_prerequisites.dart';
import 'teammate_bus_http_client.dart';

const _sessionId = 'it-http-client';

void main() {
  setUpAll(IntegrationPrerequisites.resetHttpOverrides);

  late TeamBus bus;
  late TeammateBusMcpGateway gateway;
  late TeammateBusHttpClient leaderClient;

  setUp(() async {
    bus = TeamBus(launcher: FakeMemberLauncher());
    gateway = TeammateBusMcpGateway();
    await gateway.ensureStarted();
    gateway.register(
      sessionId: _sessionId,
      handler: TeammateBusMcpHandler(bus: bus),
    );
    leaderClient = TeammateBusHttpClient(
      endpoint: gateway.mcpEndpoint,
      memberId: 'leader',
      sessionId: _sessionId,
    );
  });

  tearDown(() async {
    leaderClient.close(force: true);
    await gateway.unregister(_sessionId);
  });

  test('initialize returns protocol + tools capability', () async {
    final res = await leaderClient.initialize();
    expect((res['result'] as Map)['protocolVersion'], '2025-06-18');
  });

  test('send_message routes by X-Member header', () async {
    final target = AgentNode.test(
      memberId: 'worker',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );
    bus.declareMember(target);

    await leaderClient.sendMessage(to: 'worker', content: 'hi');

    expect(target.inbox.isEmpty, isFalse);
  });
}
