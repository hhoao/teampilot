import '../persistence/bus_message_page.dart';
import '../idle_notification.dart';
import '../team_bus.dart';
import '../team_message.dart';
import '../teammate_snapshot.dart';
import 'jsonrpc.dart';

/// 把 MCP JSON-RPC 调用分发到 [TeamBus]。纯逻辑，不依赖 HTTP。
/// [memberId] 来自传输层解析的身份头。返回 null = 通知（无响应/202）。
class TeammateBusMcpHandler {
  TeammateBusMcpHandler({required TeamBus bus, this.idGenerator = _uuidish})
    : _bus = bus;

  static const protocolVersion = '2025-06-18';
  static const serverName = 'teampilot-teammate-bus';

  final TeamBus _bus;
  final String Function() idGenerator;

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
        return JsonRpcResponse.error(
          req.id,
          -32601,
          'Method not found: ${req.method}',
        );
    }
  }

  /// wait_for_message 是长任务：返回 true 让传输层走 SSE。
  bool isLongRunning(JsonRpcRequest req) =>
      req.method == 'tools/call' && (req.params['name'] == 'wait_for_message');

  static const _toolDefs = <Map<String, Object?>>[
    {
      'name': 'list_teammates',
      'description':
          'List all team members and team config (Claude-style roster): ids, '
          'agentId, agentType, model, provider, CLI, taskId, cwd, prompt '
          'summary, plus live bus state (unread, wait_for_message, pty). '
          'Use member id in send_message(to=...).',
      'inputSchema': {
        'type': 'object',
        'additionalProperties': false,
        'properties': <String, Object?>{},
        'required': <String>[],
      },
    },
    {
      'name': 'send_message',
      'description':
          'Send a message to a teammate by member id (or "*" to broadcast).',
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
      'name': 'read_messages',
      'description':
          'Page through persisted mailbox (unread by default). Use after_id '
          'from the previous page for pagination. Set mark_read=true to '
          'consume without blocking in wait_for_message.',
      'inputSchema': {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'after_id': {'type': 'string'},
          'limit': {'type': 'integer', 'minimum': 1, 'maximum': 100},
          'unread_only': {'type': 'boolean'},
        },
        'required': <String>[],
      },
    },
    {
      'name': 'wait_for_message',
      'description':
          'Block until teammate or user (operator) messages arrive (returns a batch). '
          'No timeout — waits indefinitely. User input while you wait appears as '
          'FROM user (operator):. After handling a batch, call again.',
      'inputSchema': {
        'type': 'object',
        'additionalProperties': false,
        'properties': <String, Object?>{},
        'required': <String>[],
      },
    },
  ];

  Future<JsonRpcResponse?> _callTool(
    String memberId,
    JsonRpcRequest req,
  ) async {
    final name = req.params['name'];
    final args = req.params['arguments'] is Map
        ? Map<String, Object?>.from(req.params['arguments'] as Map)
        : const <String, Object?>{};
    switch (name) {
      case 'list_teammates':
        return _ok(req.id, _encodeRoster(memberId));
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
      case 'read_messages':
        final afterId = (args['after_id'] as String?)?.trim();
        final limit = (args['limit'] as num?)?.toInt() ?? 20;
        final unreadOnly = args['unread_only'] as bool? ?? true;
        final markRead = args['mark_read'] as bool? ?? true;
        final page = await _bus.readMessages(
          memberId,
          afterId: afterId?.isEmpty == true ? null : afterId,
          limit: limit,
          unreadOnly: unreadOnly,
          markRead: markRead,
        );
        return _ok(req.id, _encodeMessagePage(page));
      case 'wait_for_message':
        final batch = await _bus.receive(memberId);
        return _ok(req.id, _encodeBatch(batch));
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

  String _encodeRoster(String callerMemberId) {
    final snapshot = _bus.rosterSnapshot();
    if (snapshot.members.isEmpty) {
      return 'No teammates registered on the bus.';
    }
    final buffer = StringBuffer();
    final team = snapshot.team;
    if (team != null) {
      buffer.writeln('=== Team: ${team.teamName} (${team.cliTeamName}) ===');
      if (team.description.trim().isNotEmpty) {
        buffer.writeln('description: ${team.description.trim()}');
      }
      buffer.writeln('team_id: ${team.teamId}');
      buffer.writeln('team_mode: ${team.teamMode}');
      buffer.writeln('lead_agent_id: ${team.leadAgentId}');
      buffer.writeln('app_session_id: ${team.appSessionId}');
      buffer.writeln('cwd: ${team.workingDirectory}');
      if (team.additionalPaths.isNotEmpty) {
        buffer.writeln('additional_paths: ${team.additionalPaths.join(', ')}');
      }
      buffer.writeln('');
    }
    buffer.writeln(
      'Roster (${snapshot.members.length} members). You (caller): $callerMemberId',
    );
    buffer.writeln('');
    for (final t in snapshot.members) {
      buffer.writeln(_formatTeammate(t, callerMemberId == t.memberId));
      buffer.writeln('');
    }
    return buffer.toString().trimRight();
  }

  String _formatTeammate(TeammateSnapshot t, bool isSelf) {
    final p = t.profile;
    final role = p.isTeamLead ? 'leader' : 'worker';
    final lines = <String>[
      '--- ${p.memberId}${isSelf ? ' (self)' : ''} ---',
      'name: ${p.memberId}',
      'display_name: ${p.effectiveDisplayName}',
      'agentId: ${p.agentId.isEmpty ? p.memberId : p.agentId}',
      'agentType: ${p.agentType.isEmpty ? p.memberId : p.agentType}',
      'role: $role',
      if (p.agent.isNotEmpty) 'agent: ${p.agent}',
      if (p.model.isNotEmpty) 'model: ${p.model}',
      if (p.provider.isNotEmpty) 'provider: ${p.provider}',
      'cli: ${p.cli.isEmpty ? '?' : p.cli}',
      'backendType: ${p.backendType.isEmpty ? p.cli : p.backendType}',
      if (p.taskId.isNotEmpty) 'taskId: ${p.taskId}',
      if (p.cwd.isNotEmpty) 'cwd: ${p.cwd}',
      if (p.joinedAt > 0) 'joinedAt: ${p.joinedAt}',
      if (p.extraArgs.isNotEmpty) 'extraArgs: ${p.extraArgs}',
      'dangerouslySkipPermissions: ${p.dangerouslySkipPermissions}',
      'prompt: ${p.promptSummary()}',
      'bus.lifecycle: ${t.lifecycle.name}',
      'bus.activity: ${t.activity.name}',
      'bus.phase: ${t.busPhaseLabel}',
      if (t.claudeIsActive != null) 'claude.isActive: ${t.claudeIsActive}',
      'bus.unread: ${t.unreadCount}',
      'pty.running: ${t.ptyRunning}',
    ];
    return lines.join('\n');
  }

  String _encodeMessagePage(BusMessagePage page) {
    if (page.messages.isEmpty) {
      return 'No messages (total_unread=${page.totalUnread}).';
    }
    final buffer = StringBuffer(
      'Messages (${page.messages.length}, total_unread=${page.totalUnread}, '
      'has_more=${page.hasMore}',
    );
    if (page.nextAfterId != null) {
      buffer.write(', next_after_id=${page.nextAfterId}');
    }
    buffer.writeln('):');
    buffer.writeln();
    buffer.write(page.messages.map(_formatMessage).join('\n\n---\n\n'));
    return buffer.toString().trimRight();
  }

  String _encodeBatch(List<TeamMessage> batch) {
    if (batch.isEmpty) {
      return 'EMPTY: no messages (unexpected — wait_for_message should block until mail arrives).';
    }
    return batch.map(_formatMessage).join('\n\n---\n\n');
  }

  String _formatMessage(TeamMessage m) {
    if (m.from == TeamBus.userSenderId) {
      return 'FROM user (operator):\n${m.content}';
    }
    final idle = IdleNotification.parseTeamMessageContent(m.content);
    if (idle != null) {
      return 'FROM ${m.from}:\n${idle.formatForLeader()}';
    }
    return 'FROM ${m.from}:\n${m.content}';
  }

  static String _uuidish() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
  static int _seq = 0;
}
