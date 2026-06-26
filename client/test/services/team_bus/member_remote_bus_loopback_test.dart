import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_server.dart';
import 'package:teampilot/services/team_bus/remote/member_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/remote/remote_bus_mount.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';
import 'support/fake_reverse_tunnel.dart';

String _idleHttpPost({required String memberId, required String token}) =>
    'POST /idle HTTP/1.1\r\n'
    'Host: 127.0.0.1\r\n'
    '$teammateBusMcpMemberHeader: $memberId\r\n'
    '$teammateBusTokenHeader: $token\r\n'
    'Content-Length: 0\r\n'
    'Connection: close\r\n'
    '\r\n';

void main() {
  late TeamBus bus;
  late RemoteBusMount mount;
  late FakeReverseTunnel? mcpRawTunnel;
  final tunnels = <FakeReverseTunnel>[];

  setUp(() {
    bus = TeamBus(launcher: FakeMemberLauncher());
    tunnels.clear();
    mcpRawTunnel = null;
    var nextPort = 49888;
    mount = RemoteBusMount.testing(
      handler: TeammateBusMcpHandler(bus: bus),
      tunnelFactory: () {
        final tunnel = FakeReverseTunnel(port: nextPort++);
        tunnels.add(tunnel);
        mcpRawTunnel ??= tunnel;
        return tunnel;
      },
      storageFs: LocalFilesystem(),
      remoteRun: (cmd) async => cmd.contains('socat') ? '/usr/bin/socat' : '',
      arch: 'linux-x64',
      httpBusPort: 0,
    );
  });
  tearDown(() => mount.close());

  test('binding points MCP at raw tunnel and idle at separate HTTP tunnel',
      () async {
    final binding = await mount.bindLongBlockingMember('worker');
    expect(binding.mcpRawTunnelPort, mcpRawTunnel!.port);
    expect(binding.mcpRelayArgv, isNotNull);
    expect(binding.idleHttpTunnelPort, isNot(mcpRawTunnel!.port));
    expect(binding.idleUrl, 'http://127.0.0.1:${binding.idleHttpTunnelPort}/idle');

    final cfg = buildMemberBusMcpConfig(
      memberId: 'worker',
      localEndpoint: Uri.parse('http://127.0.0.1:5005/mcp'),
      longBlocking: true,
      remote: binding,
    );
    final args = (cfg['args'] as List).join(' ');
    expect(args, contains('TCP:127.0.0.1:${binding.mcpRawTunnelPort}'));
    expect(args, contains(binding.token));
    expect(args, isNot(contains('5005')));
  });

  test('idle POST over HTTP tunnel with token reaches bus /idle', () async {
    bus.declareMember(
      AgentNode.test(
        memberId: 'worker',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      ),
    );
    final server = TeammateBusMcpServer(handler: TeammateBusMcpHandler(bus: bus));
    await server.start();
    addTearDown(server.stop);

    final idleTunnels = <FakeReverseTunnel>[];
    var nextPort = 52000;
    final idleMount = RemoteBusMount.testing(
      handler: server.handler,
      httpBusPort: server.port,
      tunnelFactory: () {
        final tunnel = FakeReverseTunnel(port: nextPort++);
        idleTunnels.add(tunnel);
        return tunnel;
      },
      storageFs: LocalFilesystem(),
      remoteRun: (cmd) async => cmd.contains('socat') ? '/usr/bin/socat' : '',
      arch: 'linux-x64',
    );
    addTearDown(idleMount.close);

    final binding = await idleMount.bindLongBlockingMember('worker');
    expect(idleTunnels, hasLength(2));
    final idleTunnel = idleTunnels[1];

    final channel = FakeChannel();
    idleTunnel.emitChannel(channel);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    channel.remoteWrite(
      utf8.encode(
        _idleHttpPost(memberId: 'worker', token: binding.token),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(channel.sentText, contains('"decision":"block"'));
    expect(channel.sentText, contains('wait_for_message'));
  });

  test('wait_for_message delivered to a remote member over the tunnel', () async {
    bus.declareMember(
      AgentNode.test(
        memberId: 'worker',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      ),
    );
    final binding = await mount.bindLongBlockingMember('worker');

    final channel = FakeChannel();
    mcpRawTunnel!.emitChannel(channel);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    channel.remoteWrite(utf8.encode(
      '{"token":"${binding.token}","memberId":"worker"}\n',
    ));
    channel.remoteWrite(utf8.encode(
      '{"jsonrpc":"2.0","id":7,"method":"tools/call",'
      '"params":{"name":"wait_for_message","arguments":{}}}\n',
    ));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    bus.memberById('worker')!.inbox.deliver(
      TeamMessage(id: '1', from: 'lead', to: 'worker', content: 'ping-remote'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(channel.sentText, contains('ping-remote'));
  });
}
