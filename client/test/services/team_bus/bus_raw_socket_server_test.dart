import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/remote/bus_raw_socket_server.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';

void main() {
  late TeamBus bus;
  late BusRawSocketServer server;
  late int port;

  setUp(() async {
    bus = TeamBus(launcher: FakeMemberLauncher());
    server = BusRawSocketServer(
      handler: TeammateBusMcpHandler(bus: bus),
      token: 'T',
    );
    port = await server.start();
  });
  tearDown(() => server.close());

  test('rejects a connection whose first frame has a wrong token', () async {
    final sock = await Socket.connect('127.0.0.1', port);
    final lines = <String>[];
    final done = Completer<void>();
    sock.listen(
      (d) => lines.add(utf8.decode(d)),
      onDone: done.complete,
      onError: (_) => done.complete(),
    );
    sock.add(utf8.encode('{"token":"WRONG","memberId":"m1"}\n'));
    // Even a follow-up request must not be dispatched (connection dropped).
    sock.add(utf8.encode('{"jsonrpc":"2.0","id":1,"method":"ping"}\n'));
    await done.future.timeout(const Duration(seconds: 3));
    expect(lines, isEmpty);
  });

  test('accepts a valid token then dispatches line-delimited JSON-RPC', () async {
    final sock = await Socket.connect('127.0.0.1', port);
    final responses = <Map<String, Object?>>[];
    utf8.decoder.bind(sock).transform(const LineSplitter())
        .listen((l) {
          if (l.trim().isNotEmpty) {
            responses.add(jsonDecode(l) as Map<String, Object?>);
          }
        });
    sock.add(utf8.encode('{"token":"T","memberId":"m1"}\n'));
    sock.add(
      utf8.encode('{"jsonrpc":"2.0","id":1,"method":"initialize"}\n'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(responses, isNotEmpty);
    expect((responses.first['result'] as Map)['protocolVersion'], isNotNull);
    await sock.close();
  });

  test('delivers a wait_for_message result over the raw socket', () async {
    bus.declareMember(
      AgentNode.test(
        memberId: 'worker',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      ),
    );
    final sock = await Socket.connect('127.0.0.1', port);
    final lines = <String>[];
    utf8.decoder.bind(sock).transform(const LineSplitter())
        .listen((l) {
          if (l.trim().isNotEmpty) lines.add(l);
        });
    sock.add(utf8.encode('{"token":"T","memberId":"worker"}\n'));
    sock.add(
      utf8.encode(
        '{"jsonrpc":"2.0","id":2,"method":"tools/call",'
        '"params":{"name":"wait_for_message","arguments":{}}}\n',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // Another member sends a message → the parked wait returns it.
    bus.memberById('worker')!.inbox.deliver(
      TeamMessage(id: '1', from: 'lead', to: 'worker', content: 'hello-remote'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(lines.any((l) => l.contains('hello-remote')), isTrue);
    await sock.close();
  });

  test('framing splits coalesced + half lines correctly', () async {
    final sock = await Socket.connect('127.0.0.1', port);
    final responses = <Map<String, Object?>>[];
    utf8.decoder.bind(sock).transform(const LineSplitter())
        .listen((l) {
          if (l.trim().isNotEmpty) {
            responses.add(jsonDecode(l) as Map<String, Object?>);
          }
        });
    // handshake + first request coalesced in one write
    sock.add(utf8.encode(
      '{"token":"T","memberId":"m1"}\n{"jsonrpc":"2.0","id":1,"method":"ping"}\n',
    ));
    // a request split across two writes (half line)
    sock.add(utf8.encode('{"jsonrpc":"2.0","id":2,"meth'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    sock.add(utf8.encode('od":"ping"}\n'));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(responses.map((r) => r['id']).toSet(), {1, 2});
    await sock.close();
  });
}
