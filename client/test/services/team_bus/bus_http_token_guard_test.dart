import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/services/team_bus/remote/bus_http_token_guard.dart';

/// #3 closure: the cursor HTTP-over-tunnel path is admitted only with a matching
/// X-Bus-Token; the guard then transparently proxies to the bus HTTP port.
void main() {
  late HttpServer upstream;
  late BusHttpTokenGuard guard;

  setUp(() async {
    // Stand-in for the bus HTTP server: echoes a marker for any request.
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      req.response.statusCode = 200;
      req.response.write('bus-ok');
      await req.response.close();
    });
    guard = BusHttpTokenGuard(token: 'sekret', upstreamPort: upstream.port);
    await guard.start();
  });
  tearDown(() async {
    await guard.close();
    await upstream.close(force: true);
  });

  Future<String> sendRequest(Map<String, String> headers) async {
    final sock = await Socket.connect('127.0.0.1', guard.port);
    final out = StringBuffer();
    final done = Completer<void>();
    sock.listen(
      (d) => out.write(utf8.decode(d)),
      onDone: done.complete,
      onError: (_) => done.complete(),
    );
    final headerLines = [
      'GET /mcp HTTP/1.1',
      'host: 127.0.0.1',
      for (final e in headers.entries) '${e.key}: ${e.value}',
      'connection: close',
      '',
      '',
    ].join('\r\n');
    sock.add(utf8.encode(headerLines));
    await done.future.timeout(const Duration(seconds: 3));
    await sock.close();
    return out.toString();
  }

  test('valid X-Bus-Token is proxied to the bus', () async {
    final resp = await sendRequest({'X-Bus-Token': 'sekret', 'X-Member': 'cur'});
    expect(resp, contains('200'));
    expect(resp, contains('bus-ok'));
  });

  test('wrong X-Bus-Token is rejected with 403, never reaching the bus',
      () async {
    final resp = await sendRequest({'X-Bus-Token': 'nope', 'X-Member': 'cur'});
    expect(resp, contains('403'));
    expect(resp, isNot(contains('bus-ok')));
  });

  test('missing token is rejected', () async {
    final resp = await sendRequest({'X-Member': 'cur'});
    expect(resp, contains('403'));
    expect(resp, isNot(contains('bus-ok')));
  });
}
