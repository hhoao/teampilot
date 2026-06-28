import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_server.dart';
import 'package:teampilot/services/team_bus/remote/member_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/remote/remote_bus_binding_resolver.dart';
import 'package:teampilot/services/team_bus/remote/remote_bus_mount.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import 'support/fake_member_launcher.dart';
import 'support/fake_reverse_tunnel.dart';

void main() {
  late TeamBus bus;
  late TeammateBusMcpServer server;
  final openedTunnels = <FakeReverseTunnel>[];
  late RemoteBusMount mount;

  RemoteBusBindingResolver makeResolver() {
    var nextPort = 51000;
    mount = RemoteBusMount.testing(
      handler: server.handler,
      httpBusPort: server.port,
      tunnelFactory: () {
        final tunnel = FakeReverseTunnel(port: nextPort++);
        openedTunnels.add(tunnel);
        return tunnel;
      },
      storageFs: LocalFilesystem(),
      remoteRun: (cmd) async => cmd.contains('socat') ? '/usr/bin/socat' : '',
      arch: 'linux-x64',
    );
    return RemoteBusBindingResolver();
  }

  setUp(() async {
    bus = TeamBus(launcher: FakeMemberLauncher());
    server = TeammateBusMcpServer(handler: TeammateBusMcpHandler(bus: bus));
    await server.start();
    openedTunnels.clear();
  });
  tearDown(() async {
    await mount.close();
    await server.stop();
  });

  test('remote long-blocking member → relay binding at the MCP tunnel port',
      () async {
    final resolver = makeResolver();
    final binding = await resolver.bindMember(
      mount: mount,
      memberId: 'worker',
      cli: CliTool.claude,
    );
    expect(binding.mcpRelayArgv, isNotNull);
    expect(binding.mcpRawTunnelPort, openedTunnels.first.port);
    expect(binding.idleHttpTunnelPort, openedTunnels.last.port);
    expect(binding.idleHttpTunnelPort, isNot(binding.mcpRawTunnelPort));

    final cfg = buildMemberBusMcpConfig(
      memberId: 'worker',
      localEndpoint: server.endpoint,
      longBlocking: true,
      remote: binding,
    );
    final args = (cfg['args'] as List).join(' ');
    expect(args, contains('TCP:127.0.0.1:${binding.mcpRawTunnelPort}'));
    expect(args, isNot(contains('${server.port}')));
  });

  test('remote cursor member → HTTP-over-tunnel binding (no relay)', () async {
    final resolver = makeResolver();
    final binding = await resolver.bindMember(
      mount: mount,
      memberId: 'cur',
      cli: CliTool.cursor,
    );
    expect(binding.mcpRelayArgv, isNull);
    final cfg = buildMemberBusMcpConfig(
      memberId: 'cur',
      localEndpoint: server.endpoint,
      longBlocking: false,
      remote: binding,
    );
    expect(cfg['url'], 'http://127.0.0.1:${binding.mcpHttpTunnelPort}/mcp');
  });

  test('same mount binds multiple members', () async {
    final resolver = makeResolver();
    final a = await resolver.bindMember(
      mount: mount,
      memberId: 'a',
      cli: CliTool.claude,
    );
    final b = await resolver.bindMember(
      mount: mount,
      memberId: 'b',
      cli: CliTool.claude,
    );
    expect(a.mcpRawTunnelPort, isNot(b.mcpRawTunnelPort));
    expect(a.idleHttpTunnelPort, isNot(b.idleHttpTunnelPort));
  });

  test('closing the mount tears down its tunnels (tab dispose path)', () async {
    final resolver = makeResolver();
    await resolver.bindMember(
      mount: mount,
      memberId: 'worker',
      cli: CliTool.claude,
    );
    await mount.close();
    for (final tunnel in openedTunnels) {
      expect(tunnel.closed, isTrue);
    }
  });
}
