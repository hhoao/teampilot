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

  Future<Map<String, Object?>> readMessages({
    String? afterId,
    int limit = 20,
    bool unreadOnly = true,
    bool markRead = false,
  }) {
    return callTool('read_messages', <String, Object?>{
      if (afterId != null) 'after_id': afterId,
      'limit': limit,
      'unread_only': unreadOnly,
      'mark_read': markRead,
    });
  }

  Future<Map<String, Object?>> addTasks(List<Map<String, Object?>> tasks) {
    return callTool('add_tasks', <String, Object?>{'tasks': tasks});
  }

  Future<Map<String, Object?>> claimTask(String taskId) {
    return callTool('claim_task', <String, Object?>{'task_id': taskId});
  }

  Future<Map<String, Object?>> updateTask({
    required String taskId,
    required String status,
    String? result,
  }) {
    return callTool('update_task', <String, Object?>{
      'task_id': taskId,
      'status': status,
      if (result != null) 'result': result,
    });
  }

  Future<Map<String, Object?>> listTasks({String? status}) {
    return callTool('list_tasks', <String, Object?>{
      if (status != null) 'status': status,
    });
  }

  void close({bool force = true}) => _client.close(force: true);

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

  /// Extracts the first text block from an MCP `tools/call` JSON-RPC response.
  static String toolResultText(Map<String, Object?> response) {
    final result = response['result'] as Map;
    final content = result['content'] as List;
    return (content.first as Map)['text'] as String;
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

  /// Parses `Enqueued N task(s):\n- <id>: <title>` lines from [addTasks].
  static List<({String id, String title})> parseEnqueuedTasks(
    Map<String, Object?> response,
  ) {
    final text = toolResultText(response);
    final out = <({String id, String title})>[];
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('- ')) continue;
      final body = trimmed.substring(2);
      final colon = body.indexOf(': ');
      if (colon <= 0) continue;
      out.add((id: body.substring(0, colon), title: body.substring(colon + 2)));
    }
    return out;
  }

  static bool toolSucceeded(Map<String, Object?> response) {
    final result = response['result'];
    if (result is! Map) return false;
    return result['isError'] != true;
  }

  static bool toolFailed(Map<String, Object?> response) => !toolSucceeded(response);
}
