@Tags(['integration', 'cross-platform'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/persistence/in_memory_bus_message_log.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import '../services/team_bus/support/fake_member_launcher.dart';
import 'support/integration_prerequisites.dart';
import 'support/teammate_bus_http_client.dart';

const _sessionId = 'it-ping-pong';

/// L1-fast: same ping/pong scenario as the full ChatCubit integration test,
/// but drives the loopback HTTP teammate-bus directly (no Claude PTY).
void main() {
  late TeamBus bus;
  late InMemoryBusMessageLog messageLog;
  late TeammateBusMcpGateway gateway;
  late TeammateBusHttpClient leaderClient;
  late TeammateBusHttpClient workerClient;

  setUp(() async {
    IntegrationPrerequisites.resetHttpOverrides();
    messageLog = InMemoryBusMessageLog();
    bus = TeamBus(launcher: FakeMemberLauncher(), messageLog: messageLog);
    gateway = TeammateBusMcpGateway();
    await gateway.ensureStarted();
    gateway.register(
      sessionId: _sessionId,
      handler: TeammateBusMcpHandler(bus: bus),
    );

    bus.declareMember(
      AgentNode.test(
        memberId: 'team-lead',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      ),
    );
    bus.declareMember(
      AgentNode.test(
        memberId: 'developer',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      ),
    );

    leaderClient = TeammateBusHttpClient(
      endpoint: gateway.mcpEndpoint,
      memberId: 'team-lead',
      sessionId: _sessionId,
    );
    workerClient = TeammateBusHttpClient(
      endpoint: gateway.mcpEndpoint,
      memberId: 'developer',
      sessionId: _sessionId,
    );
    await leaderClient.initialize();
    await workerClient.initialize();
  });

  tearDown(() async {
    leaderClient.close(force: true);
    workerClient.close(force: true);
    await gateway.unregister(_sessionId);
  });

  test('team-lead and developer exchange ping/pong over HTTP MCP', () async {
    final workerWait = workerClient.waitForMessage();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await leaderClient.sendMessage(to: 'developer', content: 'ping');

    final workerRes = await workerWait;
    expect(TeammateBusHttpClient.toolResultText(workerRes), contains('ping'));

    await workerClient.sendMessage(to: 'team-lead', content: 'pong');

    final leaderRes = await leaderClient.waitForMessage();
    expect(TeammateBusHttpClient.toolResultText(leaderRes), contains('pong'));

    final workerMail = await messageLog.load('developer');
    expect(
      workerMail.any(
        (r) => r.message.from == 'team-lead' && r.message.content == 'ping',
      ),
      isTrue,
    );
    final leaderMail = await messageLog.load('team-lead');
    expect(
      leaderMail.any(
        (r) => r.message.from == 'developer' && r.message.content == 'pong',
      ),
      isTrue,
    );
  });
}
