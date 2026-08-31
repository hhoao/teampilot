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

  test(
    'accepts a valid token then dispatches line-delimited JSON-RPC',
    () async {
      final sock = await Socket.connect('127.0.0.1', port);
      final responses = <Map<String, Object?>>[];
      utf8.decoder.bind(sock).transform(const LineSplitter()).listen((l) {
        if (l.trim().isNotEmpty) {
          responses.add(jsonDecode(l) as Map<String, Object?>);
        }
      });
      sock.add(utf8.encode('{"token":"T","memberId":"m1"}\n'));
      sock.add(utf8.encode('{"jsonrpc":"2.0","id":1,"method":"initialize"}\n'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(responses, isNotEmpty);
      expect((responses.first['result'] as Map)['protocolVersion'], isNotNull);
      await sock.close();
    },
  );

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
    utf8.decoder.bind(sock).transform(const LineSplitter()).listen((l) {
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
    bus
        .memberById('worker')!
        .inbox
        .deliver(
          TeamMessage(
            id: '1',
            from: 'lead',
            to: 'worker',
            content: 'hello-remote',
          ),
        );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(lines.any((l) => l.contains('hello-remote')), isTrue);
    await sock.close();
  });

  test('framing splits coalesced + half lines correctly', () async {
    final sock = await Socket.connect('127.0.0.1', port);
    final responses = <Map<String, Object?>>[];
    utf8.decoder.bind(sock).transform(const LineSplitter()).listen((l) {
      if (l.trim().isNotEmpty) {
        responses.add(jsonDecode(l) as Map<String, Object?>);
      }
    });
    // handshake + first request coalesced in one write
    sock.add(
      utf8.encode(
        '{"token":"T","memberId":"m1"}\n{"jsonrpc":"2.0","id":1,"method":"ping"}\n',
      ),
    );
    // a request split across two writes (half line)
    sock.add(utf8.encode('{"jsonrpc":"2.0","id":2,"meth'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    sock.add(utf8.encode('od":"ping"}\n'));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(responses.map((r) => r['id']).toSet(), {1, 2});
    await sock.close();
  });

  test(
    'newer member socket displaces stale wait; live socket gets the mail',
    () async {
      bus.declareMember(
        AgentNode.test(
          memberId: 'worker',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.active,
        ),
      );

      final stale = await Socket.connect('127.0.0.1', port);
      final staleLines = <String>[];
      final staleDone = Completer<void>();
      utf8.decoder.bind(stale).transform(const LineSplitter()).listen(
        (l) {
          if (l.trim().isNotEmpty) staleLines.add(l);
        },
        onDone: () {
          if (!staleDone.isCompleted) staleDone.complete();
        },
        onError: (_) {
          if (!staleDone.isCompleted) staleDone.complete();
        },
      );
      stale.add(utf8.encode('{"token":"T","memberId":"worker"}\n'));
      stale.add(
        utf8.encode(
          '{"jsonrpc":"2.0","id":10,"method":"tools/call",'
          '"params":{"name":"wait_for_message","arguments":{}}}\n',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(bus.isWaitingForMessage('worker'), isTrue);

      final live = await Socket.connect('127.0.0.1', port);
      final liveLines = <String>[];
      utf8.decoder.bind(live).transform(const LineSplitter()).listen((l) {
        if (l.trim().isNotEmpty) liveLines.add(l);
      });
      live.add(utf8.encode('{"token":"T","memberId":"worker"}\n'));
      live.add(
        utf8.encode(
          '{"jsonrpc":"2.0","id":11,"method":"tools/call",'
          '"params":{"name":"wait_for_message","arguments":{}}}\n',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));

      bus.memberById('worker')!.inbox.deliver(
        TeamMessage(
          id: 'm1',
          from: 'lead',
          to: 'worker',
          content: 'only-live',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(
        liveLines.any((l) => l.contains('only-live')),
        isTrue,
        reason: 'newest socket must receive the mail',
      );
      expect(
        staleLines.any((l) => l.contains('only-live')),
        isFalse,
        reason: 'displaced stale socket must not steal the mail',
      );
      // Stale wait must complete somehow (error reply and/or socket close),
      // not hang forever with no JSON-RPC response.
      await staleDone.future.timeout(const Duration(seconds: 2));

      await live.close();
    },
  );

  test(
    'same-connection superseded wait writes a JSON-RPC error (no silent hang)',
    () async {
      bus.declareMember(
        AgentNode.test(
          memberId: 'worker',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.active,
        ),
      );

      // Two sockets: first wait is superseded when second wait registers.
      // (Same member, overlapping waits — tunnel flap pattern.)
      final stale = await Socket.connect('127.0.0.1', port);
      final staleLines = <String>[];
      utf8.decoder.bind(stale).transform(const LineSplitter()).listen((l) {
        if (l.trim().isNotEmpty) staleLines.add(l);
      });
      stale.add(utf8.encode('{"token":"T","memberId":"worker"}\n'));
      stale.add(
        utf8.encode(
          '{"jsonrpc":"2.0","id":20,"method":"tools/call",'
          '"params":{"name":"wait_for_message","arguments":{}}}\n',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final live = await Socket.connect('127.0.0.1', port);
      live.add(utf8.encode('{"token":"T","memberId":"worker"}\n'));
      live.add(
        utf8.encode(
          '{"jsonrpc":"2.0","id":21,"method":"tools/call",'
          '"params":{"name":"wait_for_message","arguments":{}}}\n',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));

      // Stale request id=20 must get an error (or connection close); never
      // silence. Prefer an explicit JSON-RPC error when the socket is still up.
      final gotReply = staleLines.any((l) {
        try {
          final m = jsonDecode(l) as Map<String, Object?>;
          return m['id'] == 20 && m['error'] != null;
        } on Object {
          return false;
        }
      });
      expect(
        gotReply,
        isTrue,
        reason: 'superseded wait must get a JSON-RPC error, not hang',
      );

      await stale.close();
      await live.close();
    },
  );

  test('socket disconnect cancels parked wait so a new wait can take mail', () async {
    bus.declareMember(
      AgentNode.test(
        memberId: 'worker',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      ),
    );

    final stale = await Socket.connect('127.0.0.1', port);
    stale.add(utf8.encode('{"token":"T","memberId":"worker"}\n'));
    stale.add(
      utf8.encode(
        '{"jsonrpc":"2.0","id":30,"method":"tools/call",'
        '"params":{"name":"wait_for_message","arguments":{}}}\n',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(bus.isWaitingForMessage('worker'), isTrue);

    // Abrupt peer death (tunnel gone) — must cancel the parked wait promptly,
    // not leave turnDoneBusWait until the next mail wake.
    stale.destroy();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(
      bus.isWaitingForMessage('worker'),
      isFalse,
      reason: 'socket disconnect must cancel the in-flight wait',
    );

    final live = await Socket.connect('127.0.0.1', port);
    final liveLines = <String>[];
    utf8.decoder.bind(live).transform(const LineSplitter()).listen((l) {
      if (l.trim().isNotEmpty) liveLines.add(l);
    });
    live.add(utf8.encode('{"token":"T","memberId":"worker"}\n'));
    live.add(
      utf8.encode(
        '{"jsonrpc":"2.0","id":31,"method":"tools/call",'
        '"params":{"name":"wait_for_message","arguments":{}}}\n',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    bus.memberById('worker')!.inbox.deliver(
      TeamMessage(
        id: 'm2',
        from: 'lead',
        to: 'worker',
        content: 'after-disconnect',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(
      liveLines.any((l) => l.contains('after-disconnect')),
      isTrue,
      reason: 'disconnect must free the wait so the new socket can receive',
    );
    await live.close();
  });

  test(
    'raw-socket wait parks past short idle with no bus-side timeout',
    () async {
      bus.declareMember(
        AgentNode.test(
          memberId: 'worker',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.active,
        ),
      );

      final sock = await Socket.connect('127.0.0.1', port);
      final lines = <String>[];
      utf8.decoder.bind(sock).transform(const LineSplitter()).listen((l) {
        if (l.trim().isNotEmpty) lines.add(l);
      });
      sock.add(utf8.encode('{"token":"T","memberId":"worker"}\n'));
      sock.add(
        utf8.encode(
          '{"jsonrpc":"2.0","id":40,"method":"tools/call",'
          '"params":{"name":"wait_for_message","arguments":{}}}\n',
        ),
      );
      final parkedDeadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(parkedDeadline)) {
        if (bus.isWaitingForMessage('worker')) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(bus.isWaitingForMessage('worker'), isTrue);

      // HTTP SSE pings every 20s; raw-socket emits nothing while parked.
      // Bus itself must still hold the wait (no artificial short timeout).
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(bus.isWaitingForMessage('worker'), isTrue);
      expect(
        lines,
        isEmpty,
        reason: 'no result and no ping frames on raw socket',
      );

      bus.memberById('worker')!.inbox.deliver(
        TeamMessage(
          id: 'late',
          from: 'lead',
          to: 'worker',
          content: 'after-idle',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(lines.any((l) => l.contains('after-idle')), isTrue);
      await sock.close();
    },
  );

  test(
    'short tool call completes while wait_for_message is still parked',
    () async {
      bus.declareMember(
        AgentNode.test(
          memberId: 'worker',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.active,
        ),
      );

      final sock = await Socket.connect('127.0.0.1', port);
      final responses = <Map<String, Object?>>[];
      utf8.decoder.bind(sock).transform(const LineSplitter()).listen((l) {
        if (l.trim().isEmpty) return;
        responses.add(jsonDecode(l) as Map<String, Object?>);
      });
      sock.add(utf8.encode('{"token":"T","memberId":"worker"}\n'));
      // Park a long wait first.
      sock.add(
        utf8.encode(
          '{"jsonrpc":"2.0","id":50,"method":"tools/call",'
          '"params":{"name":"wait_for_message","arguments":{}}}\n',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(bus.isWaitingForMessage('worker'), isTrue);

      // Claude issues overlapping short tools / retries on the same stdio MCP.
      // Local bridge handles these concurrently; raw-socket must too.
      sock.add(
        utf8.encode(
          '{"jsonrpc":"2.0","id":51,"method":"tools/call",'
          '"params":{"name":"list_tasks","arguments":{}}}\n',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 300));
      final listReply = responses.where((r) => r['id'] == 51).toList();
      expect(
        listReply,
        isNotEmpty,
        reason:
            'list_tasks must not queue behind a parked wait_for_message '
            '(that is how remote MCP looks "unavailable")',
      );
      expect(bus.isWaitingForMessage('worker'), isTrue);

      await sock.close();
    },
  );

  test(
    'notifications/cancelled unparks wait without waiting for mail',
    () async {
      bus.declareMember(
        AgentNode.test(
          memberId: 'worker',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.active,
        ),
      );

      final sock = await Socket.connect('127.0.0.1', port);
      final responses = <Map<String, Object?>>[];
      utf8.decoder.bind(sock).transform(const LineSplitter()).listen((l) {
        if (l.trim().isEmpty) return;
        responses.add(jsonDecode(l) as Map<String, Object?>);
      });
      sock.add(utf8.encode('{"token":"T","memberId":"worker"}\n'));
      sock.add(
        utf8.encode(
          '{"jsonrpc":"2.0","id":60,"method":"tools/call",'
          '"params":{"name":"wait_for_message","arguments":{}}}\n',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(bus.isWaitingForMessage('worker'), isTrue);

      sock.add(
        utf8.encode(
          '{"jsonrpc":"2.0","method":"notifications/cancelled",'
          '"params":{"requestId":60}}\n',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        bus.isWaitingForMessage('worker'),
        isFalse,
        reason: 'cancel must be handled while wait is parked, not queued behind it',
      );
      await sock.close();
    },
  );
}
