import '../team_bus.dart';
import '../team_message.dart';
import 'jsonrpc.dart';

/// 把 MCP JSON-RPC 调用分发到 [TeamBus]。纯逻辑，不依赖 HTTP。
/// [memberId] 来自传输层解析的身份头。返回 null = 通知（无响应/202）。
class TeammateBusMcpHandler {
  TeammateBusMcpHandler({
    required TeamBus bus,
    this.idGenerator = _uuidish,
    this.defaultWaitTimeout = const Duration(minutes: 5),
  }) : _bus = bus;

  static const protocolVersion = '2025-06-18';
  static const serverName = 'teampilot-teammate-bus';

  final TeamBus _bus;
  final String Function() idGenerator;
  final Duration defaultWaitTimeout;

  /// 控制端点：成员（经 Stop hook / plugin / 终端 watcher）报告 idle。
  void notifyIdle(String memberId) => _bus.onMemberIdle(memberId);

  Future<JsonRpcResponse?> handle(String memberId, JsonRpcRequest req) async {
    switch (req.method) {
      case 'initialize':
        return JsonRpcResponse.result(req.id, {
          'protocolVersion': protocolVersion,
          'capabilities': {'tools': <String, Object?>{}},
          'serverInfo': {'name': serverName, 'version': '1.0.0'},
        });
      case 'notifications/initialized':
      case 'notifications/cancelled':
      case 'notifications/progress':
        return null; // 通知
      case 'ping':
        return JsonRpcResponse.result(req.id, const {});
      case 'tools/list':
        return JsonRpcResponse.result(req.id, {'tools': _toolDefs});
      case 'tools/call':
        return _callTool(memberId, req);
      default:
        return JsonRpcResponse.error(req.id, -32601, 'Method not found: ${req.method}');
    }
  }

  /// wait_for_message 是长任务：返回 true 让传输层走 SSE。
  bool isLongRunning(JsonRpcRequest req) =>
      req.method == 'tools/call' &&
      (req.params['name'] == 'wait_for_message');

  static const _toolDefs = <Map<String, Object?>>[
    {
      'name': 'send_message',
      'description': 'Send a message to a teammate by member id (or "*" to broadcast).',
      'inputSchema': {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'to': {'type': 'string'},
          'content': {'type': 'string'},
        },
        'required': ['to', 'content'],
      },
    },
    {
      'name': 'wait_for_message',
      'description': 'Block until teammate messages arrive (returns a batch), or time out (empty). Call again after handling, and after an empty result, until your task is complete.',
      'inputSchema': {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'timeout_ms': {'type': 'integer'},
        },
        'required': <String>[],
      },
    },
    {
      'name': 'finish_task',
      'description': 'Leader: mark the whole task complete and tell teammates to stand down.',
      'inputSchema': {
        'type': 'object',
        'additionalProperties': false,
        'properties': {'result': {'type': 'string'}},
        'required': ['result'],
      },
    },
    {
      'name': 'leave',
      'description': 'Worker: leave the team loop; you are done.',
      'inputSchema': {
        'type': 'object',
        'additionalProperties': false,
        'properties': <String, Object?>{},
        'required': <String>[],
      },
    },
  ];

  Future<JsonRpcResponse?> _callTool(String memberId, JsonRpcRequest req) async {
    final name = req.params['name'];
    final args = req.params['arguments'] is Map
        ? Map<String, Object?>.from(req.params['arguments'] as Map)
        : const <String, Object?>{};
    switch (name) {
      case 'send_message':
        final to = (args['to'] as String?)?.trim() ?? '';
        final content = args['content'] as String? ?? '';
        final message = TeamMessage(
          id: idGenerator(),
          from: memberId,
          to: to,
          content: content,
        );
        if (to == '*') {
          await _bus.broadcast(message, materializeDeclared: true);
        } else {
          await _bus.send(message);
        }
        return _ok(req.id, 'sent');
      case 'wait_for_message':
        final ms = (args['timeout_ms'] as num?)?.toInt();
        final timeout = ms != null ? Duration(milliseconds: ms) : defaultWaitTimeout;
        final batch = await _bus.receive(memberId, timeout: timeout);
        return _ok(req.id, _encodeBatch(batch));
      case 'finish_task':
        await _bus.finishTask(memberId, args['result'] as String? ?? '');
        return _ok(req.id, 'finished');
      case 'leave':
        _bus.leave(memberId);
        return _ok(req.id, 'left');
      default:
        return JsonRpcResponse.error(req.id, -32602, 'Unknown tool: $name');
    }
  }

  JsonRpcResponse _ok(Object? id, String text) => JsonRpcResponse.result(id, {
    'content': [
      {'type': 'text', 'text': text},
    ],
    'isError': false,
  });

  String _encodeBatch(List<TeamMessage> batch) {
    if (batch.isEmpty) return 'EMPTY: no messages yet — call wait_for_message again.';
    return batch
        .map((m) => 'FROM ${m.from}:\n${m.content}')
        .join('\n\n---\n\n');
  }

  static String _uuidish() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
  static int _seq = 0;
}
