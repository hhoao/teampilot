import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/connect_relay_client.dart';

void main() {
  late _FakeRelay relay;
  late ServerSocket localTarget;
  final acceptedByLocalTarget = <Socket>[];
  late ConnectRelayClient client;

  setUp(() async {
    relay = await _FakeRelay.start();
    localTarget = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    localTarget.listen(acceptedByLocalTarget.add);
    acceptedByLocalTarget.clear();
  });

  tearDown(() async {
    await client.stop();
    for (final socket in acceptedByLocalTarget) {
      socket.destroy();
    }
    await localTarget.close();
    await relay.stop();
  });

  ConnectRelayClient buildClient({
    Future<bool> Function(ConnectRelayDialRequest request)? validateDial,
    Future<WebSocket> Function(Uri url)? connectSocket,
  }) {
    return ConnectRelayClient(
      validateDial: validateDial ?? (_) async => true,
      resolveTarget:
          (_) async => (host: InternetAddress.loopbackIPv4, port: localTarget.port),
      connectSocket: connectSocket,
      retryDelay: const Duration(milliseconds: 5),
    );
  }

  test(
    'a validated SSH dial splices bytes between the relay and local sshd',
    () async {
      client = buildClient();
      await client.start(url: relay.baseUrl, hostId: 'h1');
      await relay.waitForDesktop();

      relay.pushDial(
        channel: 'ssh',
        spliceId: 's1',
        deviceId: 'pixel-1',
        relayGrant: 'grant-token',
      );
      final phoneSide = await relay.phoneSideOf('s1');

      phoneSide.add(utf8.encode('SSH-2.0-phone\r\n'));
      await pumpUntil(() => acceptedByLocalTarget.isNotEmpty);
      final accepted = acceptedByLocalTarget.first;
      expect(
        await accepted.first.timeout(const Duration(seconds: 3)),
        utf8.encode('SSH-2.0-phone\r\n'),
      );

      accepted.add(utf8.encode('SSH-2.0-OpenSSH\r\n'));
      expect(
        (await phoneSide.first.timeout(const Duration(seconds: 3)))
            as List<int>,
        utf8.encode('SSH-2.0-OpenSSH\r\n'),
      );
    },
  );

  test(
    'a rejected dial never opens a splice nor touches the local target',
    () async {
      client = buildClient(validateDial: (_) async => false);
      await client.start(url: relay.baseUrl, hostId: 'h1');
      await relay.waitForDesktop();

      relay.pushDial(channel: 'ssh', spliceId: 's2', deviceId: 'pixel-1');

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(relay.spliceConnections, isEmpty);
      expect(acceptedByLocalTarget, isEmpty);
    },
  );

  test('a dial without a resolvable target is rejected', () async {
    client = ConnectRelayClient(
      validateDial: (_) async => true,
      resolveTarget: (_) async => null,
      retryDelay: const Duration(milliseconds: 5),
    );
    await client.start(url: relay.baseUrl, hostId: 'h1');
    await relay.waitForDesktop();

    relay.pushDial(channel: 'pair', spliceId: 's3');

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(relay.spliceConnections, isEmpty);
    expect(acceptedByLocalTarget, isEmpty);
  });

  test('reconnects to the relay after the register socket drops', () async {
    var starts = 0;
    client = buildClient(
      connectSocket: (url) async {
        starts += 1;
        return WebSocket.connect(url.toString());
      },
    );
    await client.start(url: relay.baseUrl, hostId: 'h1');
    await relay.waitForDesktop();
    expect(starts, 1);

    await relay.dropDesktop();
    await pumpUntil(() => starts >= 2);

    expect(starts, greaterThanOrEqualTo(2));
    expect(client.isConnected, isTrue);
  });
}

Future<void> pumpUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition was never met');
}

/// Minimal in-process relay: upgrades /register and /splice like the real
/// tool so the client exercises its production WebSocket path.
class _FakeRelay {
  HttpServer? _server;
  WebSocket? _desktopSide;
  var _dropped = Completer<void>();
  final _phoneSides = <String, WebSocket>{};
  final spliceConnections = <String>[];

  static Future<_FakeRelay> start() async {
    final relay = _FakeRelay();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    relay._server = server;
    server.listen((request) async {
      switch (request.uri.path) {
        case '/register':
          final socket = await WebSocketTransformer.upgrade(request);
          relay._desktopSide = socket;
          relay._dropped = Completer<void>();
          unawaited(
            socket.done.whenComplete(() {
              if (!relay._dropped.isCompleted) relay._dropped.complete();
            }),
          );
        case '/splice':
          final id = request.uri.queryParameters['id']!;
          relay.spliceConnections.add(id);
          final socket = await WebSocketTransformer.upgrade(request);
          relay._phoneSides.remove(id)?.close();
          relay._phoneSides[id] = socket;
        default:
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
      }
    });
    return relay;
  }

  Uri get baseUrl =>
      Uri(scheme: 'ws', host: '127.0.0.1', port: _server?.port ?? 0);

  Future<void> waitForDesktop() => pumpUntil(() => _desktopSide != null);

  void pushDial({
    required String channel,
    required String spliceId,
    String? deviceId,
    String? inviteToken,
    String? relayGrant,
  }) {
    _desktopSide!.add(
      jsonEncode({
        'type': 'dial',
        'channel': channel,
        'spliceId': spliceId,
        if (deviceId != null) 'deviceId': deviceId,
        if (inviteToken != null) 'inviteToken': inviteToken,
        if (relayGrant != null) 'relayGrant': relayGrant,
      }),
    );
  }

  Future<WebSocket> phoneSideOf(String spliceId) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      final side = _phoneSides[spliceId];
      if (side != null) return side;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('splice $spliceId was never opened');
  }

  Future<void> dropDesktop() async {
    await _desktopSide?.close();
    await _dropped.future;
  }

  Future<void> stop() async {
    // Drop sockets without awaiting close frames: dead peers would hang.
    _phoneSides.clear();
    unawaited(_desktopSide?.close());
    _desktopSide = null;
    await _server?.close(force: true);
    _server = null;
  }
}
