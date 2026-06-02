import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_server.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import '../support/fake_member_launcher.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  late TeamBus bus;
  late FakeMemberLauncher launcher;
  late TeammateBusMcpServer server;
  late HttpClient client;

  setUp(() async {
    launcher = FakeMemberLauncher();
    bus = TeamBus(launcher: launcher);
    server = TeammateBusMcpServer(handler: TeammateBusMcpHandler(bus: bus));
    await server.start();
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  Future<Map<String, Object?>> rpc(String member, Map<String, Object?> body) async {
    final req = await client.postUrl(server.endpoint);
    req.headers.set('content-type', 'application/json');
    req.headers.set('accept', 'application/json, text/event-stream');
    req.headers.set('X-Member', member);
    req.add(utf8.encode(jsonEncode(body)));
    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    // SSE or JSON: extract the data line if event-stream
    if (resp.headers.contentType?.mimeType == 'text/event-stream') {
      final line = text.split('\n').firstWhere((l) => l.startsWith('data:'));
      return jsonDecode(line.substring(5).trim()) as Map<String, Object?>;
    }
    return jsonDecode(text) as Map<String, Object?>;
  }

  test('initialize over real HTTP returns protocol + tools capability', () async {
    final res = await rpc('leader', {'jsonrpc': '2.0', 'id': 0, 'method': 'initialize'});
    expect((res['result'] as Map)['protocolVersion'], '2025-06-18');
  });

  test('send_message via HTTP routes by X-Member header', () async {
    final target = AgentNode.test(memberId: 'worker', state: MemberState.busy);
    bus.declareMember(target);
    await rpc('leader', {
      'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call',
      'params': {'name': 'send_message', 'arguments': {'to': 'worker', 'content': 'hi'}},
    });
    expect(target.inbox.isEmpty, isFalse);
  });

  test('POST /idle nudges member back to wait_for_message via doorbell', () async {
    final node = AgentNode.test(memberId: 'leader', state: MemberState.busy);
    bus.declareMember(node);

    final req = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/idle'),
    );
    req.headers.set('X-Member', 'leader');
    final resp = await req.close();
    await resp.drain<void>();

    expect(resp.statusCode, 204);
    expect(node.state, MemberState.busy);
    expect(launcher.woken.single.memberId, 'leader');
    expect(launcher.woken.single.notice, TeamBus.coordinationLoopNotice);
  });

  test('wait_for_message streams an SSE result when a message arrives', () async {
    bus.declareMember(AgentNode.test(memberId: 'leader', state: MemberState.busy));
    // deliver shortly after the call starts
    Future.delayed(const Duration(milliseconds: 100), () {
      bus.memberById('leader')!.inbox.deliver(
        TeamMessage(id: '1', from: 'w', to: 'leader', content: 'reply'),
      );
    });
    final res = await rpc('leader', {
      'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call',
      'params': {'name': 'wait_for_message', 'arguments': {}},
    });
    final text = ((res['result'] as Map)['content'] as List).first as Map;
    expect(text['text'], contains('reply'));
  });
}
