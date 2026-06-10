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

  Future<Map<String, Object?>> rpc(
    String member,
    Map<String, Object?> body,
  ) async {
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

  Future<Map<String, Object?>> postIdle(String member) async {
    final req = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/idle'),
    );
    req.headers.set('X-Member', member);
    req.add(utf8.encode('{}'));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    expect(resp.statusCode, HttpStatus.ok);
    if (body.trim().isEmpty) return <String, Object?>{};
    return jsonDecode(body) as Map<String, Object?>;
  }

  test(
    'initialize over real HTTP returns protocol + tools capability',
    () async {
      final res = await rpc('leader', {
        'jsonrpc': '2.0',
        'id': 0,
        'method': 'initialize',
      });
      expect((res['result'] as Map)['protocolVersion'], '2025-06-18');
    },
  );

  test('send_message via HTTP routes by X-Member header', () async {
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
    'POST /idle redirects the member back into wait_for_message',
    () async {
      final node = AgentNode.test(
        memberId: 'leader',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      );
      bus.declareMember(node);

      final json = await postIdle('leader');

      expect(json['decision'], 'block');
      expect(json['reason'], contains('wait_for_message'));
      // notifyIdle still runs: empty inbox settles at turnDoneReady, no doorbell.
      expect(node.activity, MemberActivity.turnDoneReady);
      expect(launcher.woken, isEmpty);
    },
  );

  test(
    'POST /idle keeps blocking, only fuses out after consecutive spins',
    () async {
      bus.declareMember(
        AgentNode.test(
          memberId: 'leader',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.active,
        ),
      );

      // Every idle blocks until the runaway fuse trips — no wait in between.
      for (var i = 0; i < TeammateBusMcpHandler.maxConsecutiveIdleStops; i++) {
        expect((await postIdle('leader'))['decision'], 'block');
      }
      // Spinning without ever calling wait_for_message → fuse allows the stop.
      expect(await postIdle('leader'), <String, Object?>{});
    },
  );

  test('wait_for_message resets the idle fuse', () async {
    final leader = AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );
    bus.declareMember(leader);

    // Walk right up to the fuse threshold.
    for (var i = 0; i < TeammateBusMcpHandler.maxConsecutiveIdleStops; i++) {
      expect((await postIdle('leader'))['decision'], 'block');
    }

    // A real wait (message already pending → returns immediately) clears it.
    await rpc('leader', {
      'jsonrpc': '2.0',
      'id': 8,
      'method': 'tools/call',
      'params': {
        'name': 'send_message',
        'arguments': {'to': 'leader', 'content': 'go'},
      },
    });
    await rpc('leader', {
      'jsonrpc': '2.0',
      'id': 9,
      'method': 'tools/call',
      'params': {'name': 'wait_for_message', 'arguments': <String, Object?>{}},
    });

    // Streak reset → blocks again instead of fusing out.
    expect((await postIdle('leader'))['decision'], 'block');
  });

  // NOTE: client-disconnect → park-release is verified deterministically at the
  // bus level (see bus_message_store_test.dart 'receivePending unblocks ... when
  // cancelled'). The server hooks that same CancellationToken onto the keepalive
  // write-failure signal; a socket-level disconnect test is too timing-flaky on
  // loopback (dart:io buffers SSE writes and hides the peer RST).

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
      // deliver shortly after the call starts
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

  test(
    'stop() ends an in-flight wait_for_message stream (no orphaned keepalive)',
    () async {
      bus.declareMember(
        AgentNode.test(
          memberId: 'leader',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.active,
        ),
      );
      // Open a blocking wait — no message will ever arrive on this stream.
      final req = await client.postUrl(server.endpoint);
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
      // force-close severs the socket → drain ends via EOF or HttpException;
      // either way the stream terminated (not orphaned). What must NOT happen is
      // it hanging past the timeout.
      final drained = resp
          .drain<void>()
          .catchError((Object _) {}); // connection-closed is a valid ending
      // Let the server park inside beginWait before we tear down.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bus.isWaitingForMessage('leader'), isTrue);

      // Closing the server must cancel the parked wait and end the SSE stream —
      // deterministically, not by waiting for a keepalive write to fail.
      await server.stop();

      await drained.timeout(const Duration(seconds: 2));
      expect(bus.isWaitingForMessage('leader'), isFalse);
    },
  );
}
