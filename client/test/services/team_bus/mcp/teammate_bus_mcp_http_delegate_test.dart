import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_http_delegate.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import '../support/fake_member_launcher.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  late TeamBus bus;
  late FakeMemberLauncher launcher;
  late TeammateBusMcpHttpDelegate delegate;
  late HttpServer testServer;
  late HttpClient client;
  late int port;

  setUp(() async {
    launcher = FakeMemberLauncher();
    bus = TeamBus(launcher: launcher);
    delegate = TeammateBusMcpHttpDelegate(
      handler: TeammateBusMcpHandler(bus: bus),
    );
    testServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = testServer.port;
    testServer.listen((request) async {
      if (request.method == 'POST' && request.uri.path == '/idle') {
        await delegate.handleIdleRequest(request, memberId: 'leader');
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/mcp') {
        final member = request.headers.value('x-member')?.trim() ?? '';
        await delegate.handleMcpRequest(request, memberId: member);
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await testServer.close(force: true);
  });

  Uri mcpEndpoint() => Uri.parse('http://127.0.0.1:$port/mcp');

  Future<Map<String, Object?>> rpc(
    String member,
    Map<String, Object?> body,
  ) async {
    final req = await client.postUrl(mcpEndpoint());
    req.headers.set('content-type', 'application/json');
    req.headers.set('accept', 'application/json, text/event-stream');
    req.headers.set('X-Member', member);
    req.add(utf8.encode(jsonEncode(body)));
    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    if (resp.headers.contentType?.mimeType == 'text/event-stream') {
      final line = text.split('\n').firstWhere((l) => l.startsWith('data:'));
      return jsonDecode(line.substring(5).trim()) as Map<String, Object?>;
    }
    return jsonDecode(text) as Map<String, Object?>;
  }

  test('initialize over HTTP returns protocol version', () async {
    final res = await rpc('leader', {
      'jsonrpc': '2.0',
      'id': 0,
      'method': 'initialize',
    });
    expect((res['result'] as Map)['protocolVersion'], '2025-06-18');
  });

  test('send_message routes by member', () async {
    final target = AgentNode.test(
      memberId: 'worker',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );
    bus.declareMember(target);
    await rpc('leader', {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {
        'name': 'send_message',
        'arguments': {'to': 'worker', 'content': 'hi'},
      },
    });
    expect(target.inbox.isEmpty, isFalse);
  });

  test(
    'wait_for_message streams an SSE result when a message arrives',
    () async {
      bus.declareMember(
        AgentNode.test(
          memberId: 'leader',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.active,
        ),
      );
      Future.delayed(const Duration(milliseconds: 100), () {
        bus
            .memberById('leader')!
            .inbox
            .deliver(
              TeamMessage(id: '1', from: 'w', to: 'leader', content: 'reply'),
            );
      });
      final res = await rpc('leader', {
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/call',
        'params': {'name': 'wait_for_message', 'arguments': {}},
      });
      final text = ((res['result'] as Map)['content'] as List).first as Map;
      expect(text['text'], contains('reply'));
    },
  );

  test('cancelAllStreams ends an in-flight wait_for_message stream', () async {
    bus.declareMember(
      AgentNode.test(
        memberId: 'leader',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      ),
    );
    final req = await client.postUrl(mcpEndpoint());
    req.headers.set('content-type', 'application/json');
    req.headers.set('accept', 'application/json, text/event-stream');
    req.headers.set('X-Member', 'leader');
    req.add(
      utf8.encode(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'tools/call',
          'params': {
            'name': 'wait_for_message',
            'arguments': <String, Object?>{},
          },
        }),
      ),
    );
    final resp = await req.close();
    final drained = resp.drain<void>().catchError((Object _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(bus.isWaitingForMessage('leader'), isTrue);
    expect(delegate.activeWaitStreamCount, 1);

    delegate.cancelAllStreams();

    await drained.timeout(const Duration(seconds: 2));
    expect(bus.isWaitingForMessage('leader'), isFalse);
    expect(delegate.activeWaitStreamCount, 0);
    expect(
      bus.memberById('leader')!.activity,
      MemberActivity.turnDoneReady,
      reason: 'stream cancel must not mark working',
    );
  });

  test('newer wait_for_message supersedes stale stream; live wait gets mail', () async {
    bus.declareMember(
      AgentNode.test(
        memberId: 'worker',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      ),
    );

    Future<HttpClientResponse> openWait(int id) async {
      final req = await client.postUrl(mcpEndpoint());
      req.headers.set('content-type', 'application/json');
      req.headers.set('accept', 'application/json, text/event-stream');
      req.headers.set('X-Member', 'worker');
      req.add(
        utf8.encode(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'method': 'tools/call',
            'params': {
              'name': 'wait_for_message',
              'arguments': <String, Object?>{},
            },
          }),
        ),
      );
      return req.close();
    }

    final staleResp = await openWait(10);
    final staleDrained = staleResp.drain<void>().catchError((Object _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(bus.isWaitingForMessage('worker'), isTrue);

    final liveFuture = () async {
      final resp = await openWait(11);
      final text = await resp.transform(utf8.decoder).join();
      final line = text.split('\n').firstWhere((l) => l.startsWith('data:'));
      return jsonDecode(line.substring(5).trim()) as Map<String, Object?>;
    }();

    await Future<void>.delayed(const Duration(milliseconds: 80));
    bus.memberById('worker')!.inbox.deliver(
      TeamMessage(id: 'm1', from: 'lead', to: 'worker', content: 'ping'),
    );

    final live = await liveFuture.timeout(const Duration(seconds: 3));
    final text = ((live['result'] as Map)['content'] as List).first as Map;
    expect(text['text'], contains('ping'));

    await staleDrained.timeout(const Duration(seconds: 2));
    expect(delegate.activeWaitStreamCount, 0);

    final page = await bus.memberById('worker')!.inbox.readPage();
    expect(
      page.messages,
      isEmpty,
      reason: 'live stream consumed the mail; stale must not leave a ghost unread',
    );
  });
}