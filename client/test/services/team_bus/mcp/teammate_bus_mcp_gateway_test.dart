import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
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
  late HttpClient client;

  setUp(() async {
    gateway = TeammateBusMcpGateway();
    await gateway.ensureStarted();
    busA = TeamBus(launcher: FakeMemberLauncher());
    busB = TeamBus(launcher: FakeMemberLauncher());
    regA = gateway.register(
      sessionId: 'sess-a',
      handler: TeammateBusMcpHandler(bus: busA),
    );
    gateway.register(
      sessionId: 'sess-b',
      handler: TeammateBusMcpHandler(bus: busB),
    );
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await gateway.unregister('sess-a');
    await gateway.unregister('sess-b');
  });

  Future<HttpClientResponse> postMcp({
    String? sessionId,
    String? busToken,
    required String member,
    required Map<String, Object?> body,
  }) async {
    final req = await client.postUrl(gateway.mcpEndpoint);
    req.headers.set('content-type', 'application/json');
    req.headers.set('accept', 'application/json, text/event-stream');
    req.headers.set(teammateBusMcpMemberHeader, member);
    if (sessionId != null) {
      req.headers.set(teammateBusMcpSessionHeader, sessionId);
    }
    if (busToken != null) {
      req.headers.set(teammateBusTokenHeader, busToken);
    }
    req.add(utf8.encode(jsonEncode(body)));
    return req.close();
  }

  Future<Map<String, Object?>> rpc({
    String? sessionId,
    String? busToken,
    required String member,
    required Map<String, Object?> body,
  }) async {
    final resp = await postMcp(
      sessionId: sessionId,
      busToken: busToken,
      member: member,
      body: body,
    );
    final text = await resp.transform(utf8.decoder).join();
    if (resp.headers.contentType?.mimeType == 'text/event-stream') {
      final line = text.split('\n').firstWhere((l) => l.startsWith('data:'));
      return jsonDecode(line.substring(5).trim()) as Map<String, Object?>;
    }
    return jsonDecode(text) as Map<String, Object?>;
  }

  test('two sessions on same gateway port route by X-Session', () async {
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

    expect(gateway.mcpEndpoint.port, gateway.mcpEndpoint.port);

    await rpc(
      sessionId: 'sess-a',
      member: 'leader',
      body: {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {
          'name': 'send_message',
          'arguments': {'to': 'worker', 'content': 'for-a'},
        },
      },
    );
    await rpc(
      sessionId: 'sess-b',
      member: 'leader',
      body: {
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/call',
        'params': {
          'name': 'send_message',
          'arguments': {'to': 'worker', 'content': 'for-b'},
        },
      },
    );

    expect(workerA.inbox.isEmpty, isFalse);
    expect(workerB.inbox.isEmpty, isFalse);
    expect(workerA.inbox.peekAll().single.content, 'for-a');
    expect(workerB.inbox.peekAll().single.content, 'for-b');
  });

  test('missing X-Session and invalid token returns 400', () async {
    final resp = await postMcp(
      member: 'leader',
      body: {
        'jsonrpc': '2.0',
        'id': 0,
        'method': 'initialize',
      },
    );
    expect(resp.statusCode, HttpStatus.badRequest);
    await resp.drain<void>();

    final badToken = await postMcp(
      busToken: 'not-a-real-token',
      member: 'leader',
      body: {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
      },
    );
    expect(badToken.statusCode, HttpStatus.badRequest);
    await badToken.drain<void>();
  });

  test('valid X-Bus-Token routes without X-Session', () async {
    final res = await rpc(
      busToken: regA.token,
      member: 'leader',
      body: {
        'jsonrpc': '2.0',
        'id': 0,
        'method': 'initialize',
      },
    );
    expect((res['result'] as Map)['protocolVersion'], '2025-06-18');
  });

  test(
    'unregister(sessionA) does not cancel session B active wait stream',
    () async {
      busB.declareMember(
        AgentNode.test(
          memberId: 'leader',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.active,
        ),
      );

      final waitReq = await client.postUrl(gateway.mcpEndpoint);
      waitReq.headers.set('content-type', 'application/json');
      waitReq.headers.set('accept', 'application/json, text/event-stream');
      waitReq.headers.set(teammateBusMcpSessionHeader, 'sess-b');
      waitReq.headers.set(teammateBusMcpMemberHeader, 'leader');
      waitReq.add(
        utf8.encode(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 99,
            'method': 'tools/call',
            'params': {
              'name': 'wait_for_message',
              'arguments': <String, Object?>{},
            },
          }),
        ),
      );
      final waitResp = await waitReq.close();
      final drained = waitResp.drain<void>().catchError((Object _) {});

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(busB.isWaitingForMessage('leader'), isTrue);
      expect(gateway.isSessionRegistered('sess-b'), isTrue);

      await gateway.unregister('sess-a');
      expect(gateway.isSessionRegistered('sess-a'), isFalse);
      expect(gateway.isSessionRegistered('sess-b'), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(busB.isWaitingForMessage('leader'), isTrue);

      gateway.register(
        sessionId: 'sess-a',
        handler: TeammateBusMcpHandler(bus: busA),
      );

      await gateway.unregister('sess-b');
      await drained.timeout(const Duration(seconds: 2));
      expect(busB.isWaitingForMessage('leader'), isFalse);
    },
  );

  test('isSessionRegistered reflects register/unregister', () {
    expect(gateway.isSessionRegistered('sess-a'), isTrue);
    expect(gateway.isSessionRegistered('sess-b'), isTrue);
    expect(gateway.isSessionRegistered('missing'), isFalse);
  });

  test('config includes X-Session when sessionId provided', () {
    final entry = teammateBusMcpServerConfig(
      endpoint: gateway.mcpEndpoint,
      sessionId: 'sess-a',
      memberId: 'worker-1',
    );
    final headers = entry['headers'] as Map;
    expect(headers[teammateBusMcpSessionHeader], 'sess-a');
    expect(headers[teammateBusMcpMemberHeader], 'worker-1');
  });
}
