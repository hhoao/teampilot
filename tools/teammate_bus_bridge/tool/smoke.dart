import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Mock bus + drive the compiled bridge, asserting it holds the wait open
// (forwarding pings, blocking) then forwards the eventual result.
Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  const holdSeconds = 12; // simulate a wait that resolves after 12s
  server.listen((req) async {
    final body = await utf8.decoder.bind(req).join();
    final rpc = jsonDecode(body) as Map<String, dynamic>;
    final method = rpc['method'];
    final member = req.headers.value('x-member');
    final r = req.response;
    if (method == 'tools/call' &&
        (rpc['params'] as Map)['name'] == 'wait_for_message') {
      r
        ..statusCode = 200
        ..headers.set('content-type', 'text/event-stream; charset=utf-8');
      r.write(': open\n\n');
      await r.flush();
      // ping every 2s, deliver result after holdSeconds
      final sw = Stopwatch()..start();
      Timer.periodic(const Duration(seconds: 2), (t) async {
        if (sw.elapsed.inSeconds >= holdSeconds) {
          t.cancel();
          final result = jsonEncode({
            'jsonrpc': '2.0',
            'id': rpc['id'],
            'result': {
              'content': [
                {'type': 'text', 'text': 'FROM lead: go (member=$member)'}
              ],
              'isError': false,
            },
          });
          r.write('event: message\ndata: $result\n\n');
          await r.flush();
          await r.close();
        } else {
          r.write(': ping\n\n');
          await r.flush();
        }
      });
    } else {
      // initialize / others: plain JSON
      r
        ..statusCode = 200
        ..headers.set('content-type', 'application/json; charset=utf-8')
        ..write(jsonEncode({
          'jsonrpc': '2.0',
          'id': rpc['id'],
          'result': {'ok': true, 'method': method},
        }));
      await r.close();
    }
  });
  final url = 'http://127.0.0.1:${server.port}/mcp';
  stderr.writeln('[smoke] mock bus at $url, holdSeconds=$holdSeconds');

  final proc = await Process.start('/tmp/teammate_bus_bridge',
      ['--member', 'qa', '--bus-url', url]);
  final outLines = <String>[];
  final times = <int>[];
  final sw = Stopwatch()..start();
  proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
    if (l.trim().isEmpty) return;
    outLines.add(l);
    times.add(sw.elapsed.inMilliseconds);
    stderr.writeln('[smoke] <stdout @${sw.elapsed.inMilliseconds}ms> $l');
  });
  proc.stderr.transform(utf8.decoder).listen((l) => stderr.write('[bridge] $l'));

  void send(Map<String, dynamic> m) => proc.stdin.writeln(jsonEncode(m));

  send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {}});
  await Future<void>.delayed(const Duration(milliseconds: 500));
  send({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call',
        'params': {'name': 'wait_for_message', 'arguments': {},
                   '_meta': {'progressToken': 2}}});

  await Future<void>.delayed(const Duration(seconds: holdSeconds + 3));
  await proc.stdin.close();
  proc.kill();
  await server.close(force: true);

  // Assertions
  var pass = true;
  final initOk = outLines.any((l) => l.contains('"id":1'));
  final waitLine = outLines.indexWhere((l) => l.contains('FROM lead'));
  if (!initOk) { pass = false; stderr.writeln('FAIL: no initialize response'); }
  if (waitLine < 0) { pass = false; stderr.writeln('FAIL: wait result never forwarded'); }
  else {
    final t = times[waitLine];
    if (t < holdSeconds * 1000 - 500) {
      pass = false;
      stderr.writeln('FAIL: result arrived too early (${t}ms) — did not actually block');
    } else {
      stderr.writeln('OK: result forwarded at ${t}ms (>= ${holdSeconds}s hold) — blocked correctly');
    }
  }
  stderr.writeln(pass ? '\n=== SMOKE PASS ===' : '\n=== SMOKE FAIL ===');
  exit(pass ? 0 : 1);
}
