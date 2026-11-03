// client/tool/antigravity_acp_probe.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final adapter = args.isEmpty ? 'agy_acp_server' : args.first;
  final cwd = Directory.current.path;
  final home = Directory.systemTemp.createTempSync('agy-probe-home-').path;
  final process = await Process.start(adapter, const [], environment: {
    ...Platform.environment,
    'HOME': home,
    'USERPROFILE': home,
    'SURFACE': 'teampilot-probe',
  });
  process.stderr.transform(utf8.decoder).listen(stderr.write);
  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => stdout.writeln('<< $line'));

  var id = 0;
  void send(String method, Map<String, Object?> params) {
    final message = jsonEncode({
      'jsonrpc': '2.0',
      'id': ++id,
      'method': method,
      'params': params,
    });
    stdout.writeln('>> $message');
    process.stdin.writeln(message);
  }

  send('initialize', {
    'protocolVersion': 1,
    'clientCapabilities': <String, Object?>{},
  });
  await Future<void>.delayed(const Duration(seconds: 5));
  send('session/new', {'cwd': cwd, 'mcpServers': <Object?>[]});
  await Future<void>.delayed(const Duration(seconds: 40));
  send('session/prompt', {
    'sessionId': 'probe',
    'prompt': [
      {'type': 'text', 'text': 'Reply with exactly: ok'},
    ],
  });
  await Future<void>.delayed(const Duration(seconds: 40));
  process.kill();
  stdout.writeln('HOME=$home');
}
