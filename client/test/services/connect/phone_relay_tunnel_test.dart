import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/phone_relay_tunnel.dart';

void main() {
  late _FakeRelay relay;
  late PhoneRelayTunnel tunnel;

  setUp(() async {
    relay = await _FakeRelay.start();
    tunnel = PhoneRelayTunnel();
  });

  tearDown(() async {
    await tunnel.close();
    await relay.stop();
  });

  test(
    'open exposes a loopback port that pipes bytes over the dial socket',
    () async {
      await tunnel.open(
        relayUrl: relay.wsBaseUrl,
        hostId: 'h1',
        channel: 'ssh',
        deviceId: 'pixel-1',
        relayGrant: 'grant-token',
      );

      expect(tunnel.address, InternetAddress.loopbackIPv4);
      expect(tunnel.port, greaterThan(0));

      final socket = await Socket.connect('127.0.0.1', tunnel.port);
      await pumpUntil(() => relay.dialSides.isNotEmpty);
      final dialSide = relay.dialSides.single;

      final url = relay.dialUrls.single;
      expect(url.path, '/dial');
      expect(url.queryParameters['hostId'], 'h1');
      expect(url.queryParameters['channel'], 'ssh');
      expect(url.queryParameters['deviceId'], 'pixel-1');
      expect(url.queryParameters['relayGrant'], 'grant-token');

      dialSide.add(utf8.encode('SSH-2.0-OpenSSH\r\n'));
      expect(
        await socket.first.timeout(const Duration(seconds: 3)),
        utf8.encode('SSH-2.0-OpenSSH\r\n'),
      );

      socket.add(utf8.encode('SSH-2.0-phone\r\n'));
      expect(
        (await dialSide.first.timeout(const Duration(seconds: 3))) as List<int>,
        utf8.encode('SSH-2.0-phone\r\n'),
      );
    },
  );

  test('a plain ws relay URL dials with its host and port preserved', () async {
    final captured = <Uri>[];
    final recording = PhoneRelayTunnel(
      connectSocket: (url) async {
        captured.add(url);
        return WebSocket.connect(url.toString());
      },
    );
    addTearDown(recording.close);

    await recording.open(
      relayUrl: relay.wsBaseUrl,
      hostId: 'h1',
      channel: 'pair',
      inviteToken: 'invite-token',
    );

    final socket = await Socket.connect('127.0.0.1', recording.port);
    await pumpUntil(() => captured.isNotEmpty);

    final url = captured.single;
    expect(url.scheme, 'ws');
    expect(url.host, '127.0.0.1');
    expect(url.port, relay.port);
    expect(url.path, '/dial');
    expect(url.queryParameters['inviteToken'], 'invite-token');
    expect(url.queryParameters.containsKey('relayGrant'), isFalse);
    socket.destroy();
  });

  test('close stops accepting and tears down active bridges', () async {
    await tunnel.open(
      relayUrl: relay.wsBaseUrl,
      hostId: 'h1',
      channel: 'ssh',
      relayGrant: 'g',
    );
    final socket = await Socket.connect('127.0.0.1', tunnel.port);
    await pumpUntil(() => relay.dialSides.isNotEmpty);

    final tornDown = expectLater(socket.first, throwsA(anything));
    await tunnel.close();
    await tornDown;

    expect(tunnel.isClosed, isTrue);
  });

  test('a failed dial WS closes the accepted loopback socket', () async {
    var failNext = false;
    final failing = PhoneRelayTunnel(
      connectSocket: (url) async {
        if (failNext) throw const SocketException('relay down');
        return WebSocket.connect(url.toString());
      },
    );
    addTearDown(failing.close);

    await failing.open(
      relayUrl: relay.wsBaseUrl,
      hostId: 'h1',
      channel: 'ssh',
      relayGrant: 'g',
    );
    failNext = true;

    final socket = await Socket.connect('127.0.0.1', failing.port);
    await expectLater(
      socket.first.timeout(const Duration(seconds: 3)),
      throwsA(anything),
    );
  });
}

Future<void> pumpUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition was never met');
}

/// Minimal in-process relay that upgrades /dial like the real tool.
class _FakeRelay {
  HttpServer? _server;
  final dialUrls = <Uri>[];
  final dialSides = <WebSocket>[];

  static Future<_FakeRelay> start() async {
    final relay = _FakeRelay();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    relay._server = server;
    server.listen((request) async {
      if (request.uri.path == '/dial') {
        relay.dialUrls.add(request.uri);
        relay.dialSides.add(await WebSocketTransformer.upgrade(request));
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
    return relay;
  }

  int get port => _server?.port ?? 0;

  Uri get wsBaseUrl => Uri(scheme: 'ws', host: '127.0.0.1', port: port);

  Future<void> stop() async {
    // Do not await individual WebSocket closes: a peer that died mid-handshake
    // never answers the close frame and would hang the shutdown.
    dialSides.clear();
    await _server?.close(force: true);
    _server = null;
  }
}
