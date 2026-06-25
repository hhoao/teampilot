import 'dart:convert';
import 'dart:io';

/// Loopback HTTP driver for teammate-bus MCP tools in integration tests.
class TeammateBusHttpClient {
  TeammateBusHttpClient({
    required Uri endpoint,
    required this.memberId,
    HttpClient? httpClient,
  }) : _endpoint = endpoint,
       _client = httpClient ?? HttpClient();

  final String memberId;
  final Uri _endpoint;
  final HttpClient _client;
  int _nextId = 0;

  Future<Map<String, Object?>> initialize() {
    return rpc(<String, Object?>{
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': 'initialize',
    });
  }

  Future<Map<String, Object?>> callTool(
    String name,
    Map<String, Object?> arguments,
  ) {
    return rpc(<String, Object?>{
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': 'tools/call',
      'params': <String, Object?>{
        'name': name,
        'arguments': arguments,
      },
    });
  }

  Future<Map<String, Object?>> sendMessage({
    required String to,
    required String content,
  }) {
    return callTool('send_message', <String, Object?>{
      'to': to,
      'content': content,
    });
  }

  Future<Map<String, Object?>> waitForMessage() {
    return callTool('wait_for_message', <String, Object?>{});
  }

  Future<Map<String, Object?>> listTeammates() {
    return callTool('list_teammates', <String, Object?>{});
  }

  void close({bool force = true}) => _client.close(force: force);

  Future<Map<String, Object?>> rpc(Map<String, Object?> body) async {
    final req = await _client.postUrl(_endpoint);
    req.headers.set('content-type', 'application/json');
    req.headers.set('accept', 'application/json, text/event-stream');
    req.headers.set('X-Member', memberId);
    req.add(utf8.encode(jsonEncode(body)));
    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    return _parseResponse(resp, text);
  }

  Map<String, Object?> _parseResponse(HttpClientResponse resp, String text) {
    if (resp.headers.contentType?.mimeType == 'text/event-stream') {
      final dataLines = text
          .split('\n')
          .where((line) => line.startsWith('data:'))
          .toList();
      if (dataLines.isEmpty) {
        throw StateError('SSE response had no data: lines');
      }
      // Progress notifications may precede the final result event.
      final line = dataLines.last;
      return jsonDecode(line.substring(5).trim()) as Map<String, Object?>;
    }
    return jsonDecode(text) as Map<String, Object?>;
  }
}
