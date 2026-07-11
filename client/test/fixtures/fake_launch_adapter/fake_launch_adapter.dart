/// Fixture Launch Adapter that speaks newline-delimited JSON-RPC 2.0 on
/// stdin/stdout. Used by [launch_adapter_client_test.dart].
library;

import 'dart:convert';
import 'dart:io';

void main() async {
  final sessions = <String>{};
  final stoppedSessions = <String>{};

  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    final decoded = jsonDecode(line);
    if (decoded is! Map) continue;
    final message = Map<String, Object?>.from(decoded);
    final method = message['method'] as String?;
    final id = message['id'];

    switch (method) {
      case 'initialize':
        _respond(id, {
          'protocolVersion': 1,
          'capabilities': {
            'supportsOptions': true,
            'supportsStop': true,
          },
        });
        _notify('optionsChanged', {
          'options': [
            {
              'id': 'device',
              'label': 'Device',
              'type': 'choice',
              'value': 'chrome',
              'choices': [
                {'value': 'chrome', 'label': 'Chrome'},
                {'value': 'linux', 'label': 'Linux'},
              ],
            },
          ],
        });
        _notify('configurationsChanged', {
          'configurations': [
            {
              'id': 'select_entry',
              'name': 'Select entry…',
              'type': 'flutter',
              'isAction': true,
            },
          ],
        });
      case 'launch':
        final params = _params(message);
        final sessionId = params['sessionId'] as String? ?? 'unknown';
        sessions.add(sessionId);
        _respond(id, {'accepted': true});
        if (stoppedSessions.contains(sessionId)) break;
        _notify('output', {
          'sessionId': sessionId,
          'category': 'stdout',
          'data': 'ok\n',
        });
        if (stoppedSessions.contains(sessionId) || !sessions.contains(sessionId)) {
          break;
        }
        sessions.remove(sessionId);
        _notify('exited', {
          'sessionId': sessionId,
          'exitCode': 0,
        });
      case 'stop':
        final params = _params(message);
        final sessionId = params['sessionId'] as String?;
        if (sessionId != null) {
          stoppedSessions.add(sessionId);
          if (sessions.remove(sessionId)) {
            _notify('exited', {
              'sessionId': sessionId,
              'exitCode': 130,
            });
          }
        }
        _respond(id, {'stopped': true});
      case 'provideOptions':
        _respond(id, {
          'options': [
            {
              'id': 'device',
              'label': 'Device',
              'type': 'choice',
              'value': 'chrome',
              'choices': [
                {'value': 'chrome', 'label': 'Chrome'},
                {'value': 'linux', 'label': 'Linux'},
              ],
            },
          ],
        });
      case 'configureAction':
        final params = _params(message);
        final cancelled = params['cancelled'] == true;
        if (cancelled) {
          _respond(id, {'cancelled': true});
        } else {
          _respond(id, {
            'configuration': {
              'id': 'main',
              'name': 'main.dart',
              'type': 'flutter',
              'request': 'launch',
              'target': 'lib/main.dart',
            },
            'persist': true,
          });
        }
      case 'shutdown':
        _respond(id, {'ok': true});
        exit(0);
      default:
        if (id != null) {
          stdout.writeln(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'error': {
                'code': -32601,
                'message': 'Method not found: $method',
              },
            }),
          );
        }
    }
  }
}

Map<String, Object?> _params(Map<String, Object?> message) {
  final raw = message['params'];
  if (raw is Map) {
    return Map<String, Object?>.from(raw);
  }
  return const {};
}

void _respond(Object? id, Map<String, Object?> result) {
  if (id == null) return;
  stdout.writeln(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    }),
  );
}

void _notify(String method, Map<String, Object?> params) {
  stdout.writeln(
    jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    }),
  );
}
