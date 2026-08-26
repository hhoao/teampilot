import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:teampilot_connect_relay/relay_server.dart';

void main() {
  late RelayServer relay;
  late int port;

  setUp(() async {
    relay = RelayServer();
    await relay.start(address: InternetAddress.loopbackIPv4, port: 0);
    port = relay.port;
  });

  tearDown(() async {
    await relay.stop();
  });

  Future<WebSocket> desktop() =>
      connect('ws://127.0.0.1:$port/register?hostId=desk-1');

  Future<WebSocket> splice(String id) =>
      connect('ws://127.0.0.1:$port/splice?id=$id');

  test('health endpoint answers ok', () async {
    final request = await HttpClient()
        .get(InternetAddress.loopbackIPv4.address, port, '/health');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    expect(response.statusCode, 200);
    expect(body, 'ok');
  });

  test('dial notifies the registered desktop and splices the bytes',
      () async {
    final desk = await desktop();
    final dialMessage = desk.first.timeout(defaultTimeout);

    final phone = await connect(
      'ws://127.0.0.1:$port/dial'
      '?hostId=desk-1&channel=ssh&deviceId=device-9&relayGrant=grant-abc',
    );

    final notification = jsonDecode(await dialMessage) as Map<String, Object?>;
    expect(notification['type'], 'dial');
    expect(notification['channel'], 'ssh');
    expect(notification['spliceId'], isNotEmpty);
    expect(notification['deviceId'], 'device-9');
    expect(notification['relayGrant'], 'grant-abc');
    expect(notification.containsKey('inviteToken'), isFalse);

    final tunnel = await splice(notification['spliceId'] as String);

    phone.add(utf8.encode('hello'));
    expect(
      await tunnel.first.timeout(defaultTimeout),
      utf8.encode('hello'),
    );

    tunnel.add(utf8.encode('world'));
    expect(
      (await phone.first.timeout(defaultTimeout)) as List<int>,
      utf8.encode('world'),
    );
  });

  test('a pair-channel dial forwards the invite token unchanged', () async {
    final desk = await desktop();

    unawaited(
      connect(
        'ws://127.0.0.1:$port/dial'
        '?hostId=desk-1&channel=pair&deviceId=device-9&inviteToken=invite-xyz',
      ),
    );

    final notification =
        jsonDecode(await desk.first.timeout(defaultTimeout))
            as Map<String, Object?>;
    expect(notification['channel'], 'pair');
    expect(notification['inviteToken'], 'invite-xyz');
    expect(notification.containsKey('relayGrant'), isFalse);
  });

  test('binary frames survive the splice in both directions', () async {
    final desk = await desktop();
    final phone = await connect(
      'ws://127.0.0.1:$port/dial?hostId=desk-1&channel=ssh&deviceId=d',
    );
    final notification =
        jsonDecode(await desk.first.timeout(defaultTimeout))
            as Map<String, Object?>;
    final tunnel = await splice(notification['spliceId'] as String);

    final payload = List<int>.generate(256, (i) => i);
    phone.add(payload);
    expect(
      await tunnel.first.timeout(defaultTimeout),
      payload,
    );
  });

  test('dialing an unregistered host is rejected', () async {
    await expectLater(
      connect('ws://127.0.0.1:$port/dial?hostId=nobody&channel=ssh'),
      throwsA(anyOf(isA<WebSocketException>(), isA<SocketException>())),
    );
  });

  test('re-registration moves the dial route to the newest desktop', () async {
    final old = await desktop();
    final fresh = await desktop();
    // Drain until the relay acknowledges by answering a dial on the new one.
    unawaited(old.drain<void>());

    unawaited(
      connect('ws://127.0.0.1:$port/dial?hostId=desk-1&channel=ssh&deviceId=d'),
    );
    final notification =
        jsonDecode(await fresh.first.timeout(defaultTimeout))
            as Map<String, Object?>;
    expect(notification['type'], 'dial');
  });
}

const defaultTimeout = Duration(seconds: 5);

Future<WebSocket> connect(String url) async {
  final socket = await WebSocket.connect(url).timeout(defaultTimeout);
  return socket;
}
