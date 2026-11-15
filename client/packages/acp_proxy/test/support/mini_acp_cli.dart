import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> _stayUp(String mode, File report) async {
  if (mode == 'orphan') {
    final grand = await Process.start('sleep', const ['60']);
    File('${report.path}.grand').writeAsStringSync('${grand.pid}');
  }
  await Future<void>.delayed(const Duration(days: 1));
}

/// Tiny newline JSON-RPC ACP peer for process-upstream tests.
///
/// Args: `<mode> <trace> <report>`. Writes the report before reading stdin.
/// Never prints the environment.
Future<void> main(List<String> args) async {
  final mode = args[0];
  final trace = File(args[1]);
  final report = File(args[2]);
  report.writeAsStringSync(
    '${jsonEncode({'pid': pid, 'cwd': Directory.current.path, 'KEEP': Platform.environment['KEEP'], 'DROP': Platform.environment['DROP'], 'OTHER': Platform.environment['OTHER']})}\n',
  );

  if (mode == 'stderr-flood') {
    stderr.add(List<int>.filled(256 * 1024, 0x78));
    await stderr.flush();
  }

  final incoming = StreamIterator<String>(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
  );

  Future<void> send(Map<String, Object?> message) async {
    stdout.writeln(jsonEncode(message));
    await stdout.flush();
  }

  while (await incoming.moveNext()) {
    final line = incoming.current;
    if (line.isEmpty) continue;
    final decoded = jsonDecode(line);
    if (decoded is! Map) continue;
    final message = Map<String, Object?>.from(decoded);
    final method = message['method'];
    final id = message['id'];
    if (method is String) {
      trace.writeAsStringSync(
        '${jsonEncode({'method': method, 'params': message['params']})}\n',
        mode: FileMode.append,
      );
    }
    if (id == null || mode == 'silent') continue;

    if (method == 'initialize') {
      await send({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'protocolVersion': 1,
          'agentCapabilities': {'loadSession': true},
        },
      });
      if (mode == 'exit') exit(0);
      if (mode == 'sleep' || mode == 'orphan') {
        unawaited(_stayUp(mode, report));
      }
      continue;
    }
    if (method == 'authenticate') {
      await send({'jsonrpc': '2.0', 'id': id, 'result': <String, Object?>{}});
      continue;
    }
    if (method == 'session/new') {
      await send({
        'jsonrpc': '2.0',
        'id': id,
        'result': {'sessionId': 'cli-sess'},
      });
      continue;
    }
    if (method == 'session/load') {
      if (mode == 'load-fail') {
        await send({
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': -32603, 'message': 'load failed'},
        });
        continue;
      }
      await send({'jsonrpc': '2.0', 'id': id, 'result': <String, Object?>{}});
      continue;
    }
    if (method == 'session/prompt') {
      if (mode == 'permission') {
        await send({
          'jsonrpc': '2.0',
          'id': 'perm-1',
          'method': 'session/request_permission',
          'params': {
            'sessionId': 'cli-sess',
            'options': [
              {
                'optionId': 'allow-always',
                'name': 'Allow',
                'kind': 'allow_always',
              },
            ],
          },
        });
        while (await incoming.moveNext()) {
          final nextLine = incoming.current;
          if (nextLine.isEmpty) continue;
          final next = jsonDecode(nextLine);
          if (next is Map && next['id'] == 'perm-1') {
            File(
              '${report.path}.permission',
            ).writeAsStringSync(jsonEncode(next['result']));
            break;
          }
        }
      }
      await send({
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': 'cli-sess',
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'hi'},
          },
        },
      });
      await send({
        'jsonrpc': '2.0',
        'id': id,
        'result': {'stopReason': 'end_turn'},
      });
    }
  }
}
