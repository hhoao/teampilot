import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_session_registry.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import '../support/fake_member_launcher.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  late TeammateBusMcpGateway gateway;
  late TeamBus busA;
  late TeamBus busB;
  late TeammateBusSessionRegistration regA;
  late TeammateBusSessionRegistration regB;

  setUp(() async {
    gateway = TeammateBusMcpGateway();
    await gateway.ensureStarted();
    busA = TeamBus(launcher: FakeMemberLauncher());
    busB = TeamBus(launcher: FakeMemberLauncher());
    regA = gateway.register(
      sessionId: 'sess-a',
      handler: TeammateBusMcpHandler(bus: busA),
    );
    regB = gateway.register(
      sessionId: 'sess-b',
      handler: TeammateBusMcpHandler(bus: busB),
    );
  });

  tearDown(() async {
    await gateway.unregister('sess-a');
    await gateway.unregister('sess-b');
  });

  Future<List<Map<String, Object?>>> connectAndRpc({
    required String token,
    required String memberId,
    required List<Map<String, Object?>> requests,
  }) async {
    final sock = await Socket.connect('127.0.0.1', gateway.rawSocketPort);
    final responses = <Map<String, Object?>>[];
    utf8.decoder.bind(sock).transform(const LineSplitter()).listen((line) {
      if (line.trim().isNotEmpty) {
        responses.add(jsonDecode(line) as Map<String, Object?>);
      }
    });
    sock.add(
      utf8.encode(jsonEncode({'token': token, 'memberId': memberId}) + '\n'),
    );
    for (final req in requests) {
      sock.add(utf8.encode(jsonEncode(req) + '\n'));
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sock.close();
    return responses;
  }

  test('two sessions share one raw-socket port; token routes to correct bus',
      () async {
    final workerA = AgentNode.test(
      memberId: 'worker',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );
    final workerB = AgentNode.test(
      memberId: 'worker',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );
    busA.declareMember(workerA);
    busB.declareMember(workerB);

    expect(gateway.rawSocketPort, gateway.rawSocketPort);

    final listRes = await connectAndRpc(
      token: regA.token,
      memberId: 'leader',
      requests: [
        {'jsonrpc': '2.0', 'id': 0, 'method': 'tools/list'},
      ],
    );
    expect(listRes, isNotEmpty);
    expect(listRes.first['id'], 0);
    expect((listRes.first['result'] as Map)['tools'], isA<List>());

    await connectAndRpc(
      token: regA.token,
      memberId: 'leader',
      requests: [
        {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': {
            'name': 'send_message',
            'arguments': {'to': 'worker', 'content': 'for-a'},
          },
        },
      ],
    );

    expect(workerA.inbox.isEmpty, isFalse);
    expect(workerB.inbox.isEmpty, isTrue);
    expect(workerA.inbox.peekAll().single.content, 'for-a');
  });

  test('wrong token drops the connection without dispatching RPC', () async {
    final sock = await Socket.connect('127.0.0.1', gateway.rawSocketPort);
    final lines = <String>[];
    final done = Completer<void>();
    sock.listen(
      (d) => lines.add(utf8.decode(d)),
      onDone: done.complete,
      onError: (_) => done.complete(),
    );
    sock.add(
      utf8.encode(
        jsonEncode({'token': 'not-a-real-token', 'memberId': 'leader'}) + '\n',
      ),
    );
    sock.add(
      utf8.encode(
        jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'}) + '\n',
      ),
    );
    await done.future.timeout(const Duration(seconds: 3));
    expect(lines, isEmpty);
  });
}
