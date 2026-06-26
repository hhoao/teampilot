import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/remote/member_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/remote/remote_bus_mount.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';
import 'support/fake_reverse_tunnel.dart';

/// End-to-end (no real SSH): RemoteBusMount + FakeReverseTunnel + TunnelPump +
/// real BusRawSocketServer + real TeamBus. Proves a remote long-blocking member
/// (a) gets an MCP config pointed at the tunnel port (Android-mixed fix) and
/// (b) can actually park in wait_for_message and receive a delivery back over
/// the tunnel channel.
void main() {
  late TeamBus bus;
  late RemoteBusMount mount;
  late FakeReverseTunnel tunnel;

  setUp(() {
    bus = TeamBus(launcher: FakeMemberLauncher());
    tunnel = FakeReverseTunnel(port: 49888);
    mount = RemoteBusMount.testing(
      handler: TeammateBusMcpHandler(bus: bus),
      tunnelFactory: () => tunnel,
      storageFs: LocalFilesystem(),
      remoteRun: (cmd) async => cmd.contains('socat') ? '/usr/bin/socat' : '',
      arch: 'linux-x64',
      httpBusPort: 0,
    );
  });
  tearDown(() => mount.close());

  test('binding points the remote member at the tunnel port, with relay+token',
      () async {
    final binding = await mount.bindLongBlockingMember('worker');
    expect(binding.tunnelPort, 49888);
    expect(binding.relayArgv, isNotNull);

    final cfg = buildMemberBusMcpConfig(
      memberId: 'worker',
      localEndpoint: Uri.parse('http://127.0.0.1:5005/mcp'),
      longBlocking: true,
      remote: binding,
    );
    final args = (cfg['args'] as List).join(' ');
    expect(args, contains('TCP:127.0.0.1:49888'));
    expect(args, contains(binding.token));
    // not the bare in-process bus endpoint.
    expect(args, isNot(contains('5005')));
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

    // Simulate the remote relay connecting in: the SSH reverse forward surfaces
    // a channel; the pump dials the local raw-socket server and pipes it.
    final channel = FakeChannel();
    tunnel.emitChannel(channel);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    // The relay would first send the handshake frame, then the wait_for_message
    // request — exactly what its argv encodes.
    channel.remoteWrite(utf8.encode(
      '{"token":"${binding.token}","memberId":"worker"}\n',
    ));
    channel.remoteWrite(utf8.encode(
      '{"jsonrpc":"2.0","id":7,"method":"tools/call",'
      '"params":{"name":"wait_for_message","arguments":{}}}\n',
    ));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    // Another member sends → the parked wait returns over the channel.
    bus.memberById('worker')!.inbox.deliver(
      TeamMessage(id: '1', from: 'lead', to: 'worker', content: 'ping-remote'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(channel.sentText, contains('ping-remote'));
  });
}
