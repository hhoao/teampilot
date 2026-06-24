import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
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

/// DI-testable production call-site logic (#1): the resolver decides per member
/// target + CLI which binding to produce, built over an injected FakeReverseTunnel
/// — no real SSH. Only `SshReverseTunnel.open()` against a live host is on-device.
void main() {
  late TeamBus bus;
  late TeammateBusMcpServer server;
  late FakeReverseTunnel lastTunnel;
  late int mountBuilds;

  RemoteBusBindingResolver makeResolver() {
    mountBuilds = 0;
    return RemoteBusBindingResolver(
      mountFactory: ({required memberTarget, required busServer}) async {
        mountBuilds++;
        lastTunnel = FakeReverseTunnel(port: 51000 + mountBuilds);
        return RemoteBusMount(
          handler: busServer.handler,
          httpBusPort: busServer.port,
          tunnelFactory: () => lastTunnel,
          remoteFs: LocalFilesystem(),
          remoteRun: (cmd) async => cmd.contains('socat') ? '/usr/bin/socat' : '',
          arch: 'linux-x64',
        );
      },
    );
  }

  setUp(() async {
    bus = TeamBus(launcher: FakeMemberLauncher());
    server = TeammateBusMcpServer(handler: TeammateBusMcpHandler(bus: bus));
    await server.start();
  });
  tearDown(() => server.stop());

  test('local member resolves to null (no tunnel, unchanged transport)',
      () async {
    final resolver = makeResolver();
    final res = await resolver.resolve(
      existingMount: null,
      memberTarget: RuntimeTarget.local(),
      memberId: 'm1',
      cli: CliTool.claude,
      busServer: server,
    );
    expect(res, isNull);
    expect(mountBuilds, 0);
  });

  test('remote long-blocking member → relay binding at the tunnel port',
      () async {
    final resolver = makeResolver();
    final res = await resolver.resolve(
      existingMount: null,
      memberTarget: RuntimeTarget.ssh('p1', label: 'remote'),
      memberId: 'worker',
      cli: CliTool.claude,
      busServer: server,
    );
    expect(res, isNotNull);
    expect(res!.binding.relayArgv, isNotNull); // relay-over-tunnel
    expect(res.binding.tunnelPort, lastTunnel.port);

    final cfg = buildMemberBusMcpConfig(
      memberId: 'worker',
      localEndpoint: server.endpoint,
      longBlocking: true,
      remote: res.binding,
    );
    final args = (cfg['args'] as List).join(' ');
    expect(args, contains('TCP:127.0.0.1:${lastTunnel.port}'));
    expect(args, isNot(contains('${server.port}'))); // not the bare bus port
  });

  test('remote cursor member → HTTP-over-tunnel binding (no relay)', () async {
    final resolver = makeResolver();
    final res = await resolver.resolve(
      existingMount: null,
      memberTarget: RuntimeTarget.ssh('p1', label: 'remote'),
      memberId: 'cur',
      cli: CliTool.cursor,
      busServer: server,
    );
    expect(res, isNotNull);
    expect(res!.binding.relayArgv, isNull); // HTTP, no relay
    final cfg = buildMemberBusMcpConfig(
      memberId: 'cur',
      localEndpoint: server.endpoint,
      longBlocking: false,
      remote: res.binding,
    );
    expect(cfg['url'], 'http://127.0.0.1:${res.binding.tunnelPort}/mcp');
  });

  test('existing mount is reused across members (one tunnel mount per tab)',
      () async {
    final resolver = makeResolver();
    final first = await resolver.resolve(
      existingMount: null,
      memberTarget: RuntimeTarget.ssh('p1', label: 'remote'),
      memberId: 'a',
      cli: CliTool.claude,
      busServer: server,
    );
    expect(mountBuilds, 1);
    final second = await resolver.resolve(
      existingMount: first!.mount,
      memberTarget: RuntimeTarget.ssh('p1', label: 'remote'),
      memberId: 'b',
      cli: CliTool.claude,
      busServer: server,
    );
    expect(mountBuilds, 1); // not rebuilt
    expect(identical(first.mount, second!.mount), isTrue);
  });

  test('closing the mount tears down its tunnel (tab dispose path)', () async {
    final resolver = makeResolver();
    final res = await resolver.resolve(
      existingMount: null,
      memberTarget: RuntimeTarget.ssh('p1', label: 'remote'),
      memberId: 'worker',
      cli: CliTool.claude,
      busServer: server,
    );
    await res!.mount.close();
    expect(lastTunnel.closed, isTrue);
  });
}
