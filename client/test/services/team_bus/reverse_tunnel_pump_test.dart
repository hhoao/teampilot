import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/remote/bus_raw_socket_server.dart';
import 'package:teampilot/services/team_bus/remote/reverse_tunnel.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';
import 'support/fake_reverse_tunnel.dart';

void main() {
  test('pump pipes a tunnel channel to the local bus raw-socket end to end',
      () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(
      AgentNode.test(
        memberId: 'worker',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      ),
    );
    final server = BusRawSocketServer(
      handler: TeammateBusMcpHandler(bus: bus),
      token: 'T',
    );
    final q = await server.start();
    addTearDown(server.close);

    final tunnel = FakeReverseTunnel(port: 12345);
    final pump = TunnelPump(tunnel: tunnel, localPort: q);
    await pump.start();
    addTearDown(pump.stop);

    final ch = FakeChannel();
    tunnel.emitChannel(ch); // remote member connects

    // token handshake + a blocking wait_for_message, over the tunnel channel.
    ch.remoteWrite(utf8.encode('{"token":"T","memberId":"worker"}\n'));
    ch.remoteWrite(
      utf8.encode(
        '{"jsonrpc":"2.0","id":1,"method":"tools/call",'
        '"params":{"name":"wait_for_message","arguments":{}}}\n',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    // Lead sends to the remote member → it must arrive back on the channel.
    bus.memberById('worker')!.inbox.deliver(
      TeamMessage(id: '1', from: 'lead', to: 'worker', content: 'tunneled-hi'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(ch.sentText, contains('tunneled-hi'));
  });
}
