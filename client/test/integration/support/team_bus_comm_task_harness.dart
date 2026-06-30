import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_server.dart';
import 'package:teampilot/services/team_bus/persistence/in_memory_bus_message_log.dart';
import 'package:teampilot/services/team_bus/tasks/task_queue.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/teammate_roster_profile.dart';

import '../../services/team_bus/support/fake_member_launcher.dart';
import 'integration_prerequisites.dart';
import 'teammate_bus_http_client.dart';

/// Declarative roster entry for HTTP integration tests.
typedef BusMemberSpec = ({
  String id,
  bool isLead,
  Set<String> capabilities,
  MemberLifecycle lifecycle,
  MemberActivity activity,
});

const kDefaultTaskTeamMembers = <BusMemberSpec>[
  (
    id: 'team-lead',
    isLead: true,
    capabilities: <String>{},
    lifecycle: MemberLifecycle.running,
    activity: MemberActivity.active,
  ),
  (
    id: 'backend-dev',
    isLead: false,
    capabilities: {'backend'},
    lifecycle: MemberLifecycle.running,
    activity: MemberActivity.turnDoneReady,
  ),
  (
    id: 'frontend-dev',
    isLead: false,
    capabilities: {'frontend'},
    lifecycle: MemberLifecycle.running,
    activity: MemberActivity.turnDoneReady,
  ),
];

/// Loopback TeamBus + task queue + HTTP MCP clients for integration tests.
class TeamBusCommTaskHarness {
  TeamBusCommTaskHarness._({
    required this.bus,
    required this.launcher,
    required this.server,
    required this.clients,
    required this.messageLog,
  });

  final TeamBus bus;
  final FakeMemberLauncher launcher;
  final TeammateBusMcpServer server;
  final Map<String, TeammateBusHttpClient> clients;
  final InMemoryBusMessageLog messageLog;

  TeammateBusHttpClient clientFor(String memberId) => clients[memberId]!;

  static Future<TeamBusCommTaskHarness> create({
    List<BusMemberSpec> members = kDefaultTaskTeamMembers,
    int Function()? clock,
  }) async {
    IntegrationPrerequisites.resetHttpOverrides();
    final messageLog = InMemoryBusMessageLog();
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(
      launcher: launcher,
      messageLog: messageLog,
      clock: clock,
      taskQueue: TaskQueue(clock: clock),
    );
    for (final spec in members) {
      bus.declareMember(
        AgentNode(
          profile: TeammateRosterProfile.minimal(
            spec.id,
            isTeamLead: spec.isLead,
            capabilities: spec.capabilities,
          ),
          lifecycle: spec.lifecycle,
          activity: spec.activity,
        ),
      );
    }

    final server = TeammateBusMcpServer(
      handler: TeammateBusMcpHandler(bus: bus),
    );
    await server.start();

    final clients = <String, TeammateBusHttpClient>{};
    for (final spec in members) {
      final c = TeammateBusHttpClient(
        endpoint: server.endpoint,
        memberId: spec.id,
      );
      await c.initialize();
      clients[spec.id] = c;
    }

    return TeamBusCommTaskHarness._(
      bus: bus,
      launcher: launcher,
      server: server,
      clients: clients,
      messageLog: messageLog,
    );
  }

  Future<void> dispose() async {
    for (final c in clients.values) {
      c.close(force: true);
    }
    await server.stop();
    bus.dispose();
  }
}
