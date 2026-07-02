import 'dart:convert';

import '../../../utils/logger.dart';
import '../artifacts/artifact_exceptions.dart';
import '../artifacts/artifact_handle.dart';
import '../artifacts/artifact_transfer_service.dart';
import '../cancellation.dart';
import '../persistence/bus_message_page.dart';
import '../idle_notification.dart';
import '../tasks/task_router.dart';
import '../tasks/team_task.dart';
import '../team_bus.dart';
import '../team_message.dart';
import '../teammate_snapshot.dart';
import 'jsonrpc.dart';
import 'mcp_method.dart';
import 'tools/add_tasks_tool.dart';
import 'tools/claim_task_tool.dart';
import 'tools/fetch_artifact_tool.dart';
import 'tools/publish_artifact_tool.dart';
import 'tools/read_messages_tool.dart';
import 'tools/send_message_tool.dart';
import 'tools/teammate_bus_tool_name.dart';
import 'tools/teammate_bus_tools.dart';
import 'tools/update_task_tool.dart';
import 'tools/list_tasks_tool.dart';
import 'wait_cancel_registry.dart';

/// 流式 `wait_for_message` 的投递句柄：响应体 + 「送达确认 / 断连回滚」两个钩子。
class WaitDelivery {
  const WaitDelivery({
    required this.response,
    required this.confirm,
    required this.abort,
  });

  final JsonRpcResponse response;

  /// 结果成功写回 SSE 后调：把这批标记已读。
  final Future<void> Function() confirm;

  /// 结果写回失败（客户端断连）后调：把这批放回信箱，避免丢消息。
  final void Function() abort;
}

/// 把 MCP JSON-RPC 调用分发到 [TeamBus]。纯逻辑，不依赖 HTTP。
/// [memberId] 来自传输层解析的身份头。返回 null = 通知（无响应/202）。
class TeammateBusMcpHandler {
  TeammateBusMcpHandler({
    required TeamBus bus,
    String Function()? idGenerator,
    this.forceWaitBeforeStop = true,
    bool Function(String memberId)? forceWaitForMember,
    ArtifactTransferService? artifacts,
    WaitCancelRegistry? waitCancels,
  }) : _bus = bus,
       _forceWaitForMember = forceWaitForMember,
       _artifacts = artifacts,
       waitCancels = waitCancels ?? WaitCancelRegistry(),
       idGenerator = idGenerator ?? bus.newMessageId;

  /// 团队配置:成员 turn 结束时是否强制推回 `wait_for_message`(见
  /// [idleStopDecision])。false 时允许成员正常停止("休息")。
  final bool forceWaitBeforeStop;

  /// 成员级 forceWaitBeforeStop 解析（null=全员用 [forceWaitBeforeStop]）。cursor 等
  /// push-投递 CLI 解析为 false:正常停到 idle-at-prompt,改由门铃(stdin 注入 +
  /// read_messages)投递,因其 MCP 工具调用有 ~60s 硬限、无法阻塞在 wait_for_message。
  final bool Function(String memberId)? _forceWaitForMember;

  bool _resolveForceWait(String memberId) =>
      _forceWaitForMember?.call(memberId) ?? forceWaitBeforeStop;

  static const protocolVersion = '2025-06-18';
  static const serverName = 'teampilot-teammate-bus';

  /// 保险丝：连续多少次 idle（中间一次 `wait_for_message` 都没调）后放行 stop。
  /// 健康循环里每次 block 后成员都会去调 wait（[beginWait] 清零），streak 恒为 1；
  /// 只有成员空转、从不进 wait 时 streak 才会爬升到这个阈值，触发放行防跑飞。
  static const maxConsecutiveIdleStops = 3;

  /// 每个成员连续 idle（未进 wait）的次数，喂给上面的保险丝。
  final Map<String, int> _idleStreak = <String, int>{};

  void _noteEnteredWaitLoop(String memberId) => _idleStreak[memberId] = 0;

  final TeamBus _bus;
  final String Function() idGenerator;

  /// Cross-machine artifact transfer (publish/list/fetch). Null = the three
  /// artifact tools are neither advertised nor dispatchable (gated like the
  /// task-queue tools are on [TeamBus.hasTaskQueue]).
  final ArtifactTransferService? _artifacts;

  /// In-flight streaming `wait_for_message` calls keyed by JSON-RPC request id.
  final WaitCancelRegistry waitCancels;

  /// 控制端点：成员（经 Stop hook / plugin / 终端 watcher）报告 idle。
  void notifyIdle(String memberId) => _bus.onMemberIdle(memberId);

  /// Stop-hook 拦截语：把成员推回 `wait_for_message`，不让它结束 turn。
  static const stopRedirectReason =
      '[teammate-bus] Do not stop. Call wait_for_message — it blocks until you '
      'have something to do and returns either teammate/operator messages or a '
      'task claimed for you from the work queue. You coordinate through the '
      'bus, not by ending your turn.';

  /// Stop hook 的 JSON 响应体：默认永远回 `decision:block`，把成员一直推回
  /// `wait_for_message`（永不主动结束 turn）。仅当该成员连续 idle 超过
  /// [maxConsecutiveIdleStops] 次、其间一次 `wait_for_message` 都没调（[beginWait]
  /// 会清零）时，才返回 `{}` 放行 —— 这是防模型空转烧 token 的唯一逃生阀，
  /// 故意不看 Claude 的 `stop_hook_active`。
  ///
  /// 团队关掉 [forceWaitBeforeStop] 时直接回 `{}` 放行：成员可正常停止("休息")，
  /// 不再被推回 `wait_for_message`。
  String idleStopDecision(String memberId) {
    if (!_resolveForceWait(memberId)) {
      _idleStreak[memberId] = 0;
      return '{}';
    }
    final streak = (_idleStreak[memberId] ?? 0) + 1;
    _idleStreak[memberId] = streak;
    if (streak > maxConsecutiveIdleStops) {
      _idleStreak[memberId] = 0;
      return '{}';
    }
    return jsonEncode(<String, Object?>{
      'decision': 'block',
      'reason': stopRedirectReason,
    });
  }

  Future<JsonRpcResponse?> handle(String memberId, JsonRpcRequest req) async {
    switch (req.method) {
      case McpMethod.initialize:
        return JsonRpcResponse.result(req.id, {
          'protocolVersion': protocolVersion,
          'capabilities': {'tools': <String, Object?>{}},
          'serverInfo': {'name': serverName, 'version': '1.0.0'},
        });
      case McpMethod.notificationsInitialized:
      case McpMethod.notificationsProgress:
        return null; // 通知
      case McpMethod.notificationsCancelled:
        _handleCancelledNotification(req);
        return null;
      case McpMethod.ping:
        return JsonRpcResponse.result(req.id, const {});
      case McpMethod.toolsList:
        return JsonRpcResponse.result(req.id, {
          'tools': listAdvertisedTeammateBusTools(
            hasTaskQueue: _bus.hasTaskQueue,
            hasArtifacts: _artifacts != null,
          ),
        });
      case McpMethod.toolsCall:
        return _callTool(memberId, req);
      default:
        return JsonRpcResponse.error(
          req.id,
          JsonRpcErrorCode.methodNotFound,
          'Method not found: ${req.method}',
        );
    }
  }

  /// wait_for_message 是长任务：返回 true 让传输层走 SSE。
  bool isLongRunning(JsonRpcRequest req) =>
      req.method == McpMethod.toolsCall &&
      req.toolName == TeammateBusToolName.waitForMessage;

  void _handleCancelledNotification(JsonRpcRequest req) {
    final params = req.params;
    final requestId =
        params[McpParams.requestId] ?? params[McpParams.requestIdSnake];
    if (requestId == null) return;
    if (waitCancels.cancel(requestId)) {
      appLogger.d(
        '[teammate-bus-mcp] wait cancelled via notifications/cancelled '
        'requestId=$requestId',
      );
    }
  }

  /// 流式 `wait_for_message`：抽干热信箱但 **不** 标记已读，连同 confirm/abort
  /// 钩子返回给传输层 —— 仅当结果成功写回 SSE 后 [WaitDelivery.confirm] 才标记
  /// 已读；客户端断连则 [WaitDelivery.abort] 把批次放回信箱，避免丢消息。
  Future<WaitDelivery> beginWait(
    String memberId,
    JsonRpcRequest req, {
    CancellationToken? cancel,
  }) async {
    // 成员真的进了 wait 循环 → 健康，清零空转保险丝（见 [idleStopDecision]）。
    _noteEnteredWaitLoop(memberId);
    final outcome = await _bus.receiveWork(memberId, cancel: cancel);
    switch (outcome) {
      case MessageWork(:final messages):
        final ids = [for (final m in messages) m.id];
        return WaitDelivery(
          response: _ok(req.id, _encodeBatch(messages)),
          confirm: () => _bus.acknowledgeDelivery(memberId, ids),
          abort: () => _bus.redeliver(memberId, messages),
        );
      case TaskWork(:final task):
        // 任务已原子认领；写回失败则退回 pending（比等租约回收更及时）。
        return WaitDelivery(
          response: _ok(req.id, _encodeTaskAssignment(task)),
          confirm: () async {},
          abort: () => _bus.releaseTask(task.id),
        );
      case EmptyWork():
        return WaitDelivery(
          response: _ok(req.id, _encodeBatch(const [])),
          confirm: () async {},
          abort: () {},
        );
    }
  }

  Future<JsonRpcResponse?> _callTool(
    String memberId,
    JsonRpcRequest req,
  ) async {
    final tool = req.toolName;
    if (tool == null) {
      return JsonRpcResponse.error(
        req.id,
        JsonRpcErrorCode.invalidParams,
        'Unknown tool: ${req.params[McpParams.toolName]}',
      );
    }
    final args = req.toolArguments;
    switch (tool) {
      case TeammateBusToolName.listTeammates:
        return _ok(req.id, _encodeRoster(memberId));
      case TeammateBusToolName.sendMessage:
        final to = (args[SendMessageTool.to] as String?)?.trim() ?? '';
        final content = args[SendMessageTool.content] as String? ?? '';
        if (to.isEmpty) {
          return _toolError(req.id, 'send_message requires a non-empty "to".');
        }
        final message = TeamMessage(
          id: idGenerator(),
          from: memberId,
          to: to,
          content: content,
        );
        if (to == '*') {
          await _bus.broadcast(message, materializeDeclared: true);
          return _ok(req.id, 'sent');
        }
        final outcome = await _bus.send(message);
        if (!outcome.delivered) {
          return _toolError(
            req.id,
            'Message not delivered (${outcome.reason}): recipient "$to" '
            'is not on the bus.${_unknownRecipientHint()}',
          );
        }
        final resolved = outcome.memberId!;
        if (resolved == to) {
          return _ok(req.id, 'sent');
        }
        return _ok(req.id, 'sent to $resolved (resolved from agentId "$to")');
      case TeammateBusToolName.readMessages:
        final afterId = (args[ReadMessagesTool.afterId] as String?)?.trim();
        final limit = (args[ReadMessagesTool.limit] as num?)?.toInt() ?? 20;
        final unreadOnly =
            args[ReadMessagesTool.unreadOnly] as bool? ?? true;
        // 默认浏览不消费（与工具描述一致）；wait_for_message 才是消费路径。
        final markRead = args[ReadMessagesTool.markRead] as bool? ?? false;
        final page = await _bus.readMessages(
          memberId,
          afterId: afterId?.isEmpty == true ? null : afterId,
          limit: limit,
          unreadOnly: unreadOnly,
          markRead: markRead,
        );
        return _ok(req.id, _encodeMessagePage(page));
      case TeammateBusToolName.waitForMessage:
        _noteEnteredWaitLoop(memberId);
        final outcome = await _bus.receiveWork(memberId);
        switch (outcome) {
          case MessageWork(:final messages):
            await _bus.acknowledgeDelivery(
              memberId,
              [for (final m in messages) m.id],
            );
            return _ok(req.id, _encodeBatch(messages));
          case TaskWork(:final task):
            return _ok(req.id, _encodeTaskAssignment(task));
          case EmptyWork():
            return _ok(req.id, _encodeBatch(const []));
        }
      case TeammateBusToolName.addTasks:
        if (!_bus.hasTaskQueue) {
          return JsonRpcResponse.error(
            req.id,
            JsonRpcErrorCode.invalidParams,
            'No task queue',
          );
        }
        final raw = args[AddTasksTool.tasks];
        final drafts = <TeamTaskDraft>[
          for (final item in (raw is List ? raw : const []))
            if (item is Map)
              TeamTaskDraft(
                title: item[AddTasksTool.title] as String? ?? '',
                brief: item[AddTasksTool.brief] as String? ?? '',
                dependsOn: [
                  for (final d
                      in (item[AddTasksTool.dependsOn] as List?) ?? const [])
                    if (d is String) d,
                ],
                requiredCapabilities: {
                  for (final c in (item[AddTasksTool.requiredCapabilities]
                          as List?) ??
                      const [])
                    if (c is String && c.trim().isNotEmpty) c.trim(),
                },
                preferredCapabilities: {
                  for (final c in (item[AddTasksTool.preferredCapabilities]
                          as List?) ??
                      const [])
                    if (c is String && c.trim().isNotEmpty) c.trim(),
                },
                preferredAssignee: ((item[AddTasksTool.preferredAssignee]
                                as String?)
                            ?.trim() ??
                        '')
                        .isEmpty
                    ? null
                    : (item[AddTasksTool.preferredAssignee] as String).trim(),
              ),
        ];
        final created = _bus.addTasks(memberId, drafts);
        return _ok(req.id, 'Enqueued ${created.length} task(s):\n'
            '${created.map((t) => '- ${t.id}: ${t.title}').join('\n')}');
      case TeammateBusToolName.updateTask:
        if (!_bus.hasTaskQueue) {
          return JsonRpcResponse.error(
            req.id,
            JsonRpcErrorCode.invalidParams,
            'No task queue',
          );
        }
        final taskId = (args[UpdateTaskTool.taskId] as String?)?.trim() ?? '';
        final status =
            TaskStatus.parse(args[UpdateTaskTool.status] as String?);
        if (!status.isTerminal) {
          return _ok(req.id,
              'Invalid status. Use done | failed | cancelled.');
        }
        final ok = _bus.updateTask(
          taskId,
          status,
          result: args[UpdateTaskTool.result] as String?,
          byMember: memberId,
        );
        return _ok(req.id,
            ok ? 'Task $taskId -> ${status.name}.' : 'Update rejected '
                '(unknown task or not the claiming worker): $taskId');
      case TeammateBusToolName.listTasks:
        if (!_bus.hasTaskQueue) {
          return JsonRpcResponse.error(
            req.id,
            JsonRpcErrorCode.invalidParams,
            'No task queue',
          );
        }
        final filter = (args[ListTasksTool.status] as String?)?.trim();
        final status = (filter == null || filter.isEmpty)
            ? null
            : TaskStatus.parse(filter);
        return _ok(
            req.id, _encodeTasks(_bus.listTasks(status: status), memberId));
      case TeammateBusToolName.claimTask:
        if (!_bus.hasTaskQueue) {
          return JsonRpcResponse.error(
            req.id,
            JsonRpcErrorCode.invalidParams,
            'No task queue',
          );
        }
        final taskId = (args[ClaimTaskTool.taskId] as String?)?.trim() ?? '';
        final claimed = _bus.claimSpecificTask(taskId, memberId);
        if (claimed == null) {
          return _toolError(
            req.id,
            'Could not claim "$taskId" (gone, already claimed, blocked, or you '
            'are not eligible).',
          );
        }
        return _ok(req.id, _encodeTaskAssignment(claimed));
      case TeammateBusToolName.publishArtifact:
        return _publishArtifact(memberId, req, args);
      case TeammateBusToolName.listArtifacts:
        return _listArtifacts(req);
      case TeammateBusToolName.fetchArtifact:
        return _fetchArtifact(memberId, req, args);
    }
  }

  Future<JsonRpcResponse> _publishArtifact(
    String memberId,
    JsonRpcRequest req,
    Map<String, Object?> args,
  ) async {
    final artifacts = _artifacts;
    if (artifacts == null) {
      return JsonRpcResponse.error(
        req.id,
        JsonRpcErrorCode.invalidParams,
        'No artifact transfer',
      );
    }
    final path = (args[PublishArtifactTool.path] as String?)?.trim() ?? '';
    final name = (args[PublishArtifactTool.name] as String?)?.trim() ?? '';
    if (path.isEmpty || name.isEmpty) {
      return _toolError(
        req.id,
        'publish_artifact requires a non-empty "path" and "name".',
      );
    }
    final kind = ArtifactKind.tryParse(args[PublishArtifactTool.kind] as String?);
    if (kind == null) {
      return _toolError(
        req.id,
        'Only kind=file is supported (directory/tar transfer is not yet '
        'available).',
      );
    }
    final overwrite = args[PublishArtifactTool.overwrite] as bool? ?? false;
    try {
      final handle = await artifacts.publish(
        publisherMemberId: memberId,
        path: path,
        name: name,
        kind: kind,
        overwrite: overwrite,
      );
      return _ok(
        req.id,
        'Published "${handle.name}" (${handle.sizeBytes} bytes). Teammates can '
        'fetch_artifact(name: "${handle.name}", destPath: ...).',
      );
    } on ArtifactException catch (e) {
      return _toolError(req.id, e.toString());
    }
  }

  JsonRpcResponse _listArtifacts(JsonRpcRequest req) {
    final artifacts = _artifacts;
    if (artifacts == null) {
      return JsonRpcResponse.error(
        req.id,
        JsonRpcErrorCode.invalidParams,
        'No artifact transfer',
      );
    }
    final handles = artifacts.list();
    if (handles.isEmpty) {
      return _ok(req.id, 'No artifacts published.');
    }
    final lines = <String>['Artifacts (${handles.length}):'];
    for (final h in handles) {
      lines.add('- ${h.name} (by ${h.publisherMemberId}, ${h.sizeBytes} bytes)');
    }
    return _ok(req.id, lines.join('\n'));
  }

  Future<JsonRpcResponse> _fetchArtifact(
    String memberId,
    JsonRpcRequest req,
    Map<String, Object?> args,
  ) async {
    final artifacts = _artifacts;
    if (artifacts == null) {
      return JsonRpcResponse.error(
        req.id,
        JsonRpcErrorCode.invalidParams,
        'No artifact transfer',
      );
    }
    final name = (args[FetchArtifactTool.name] as String?)?.trim() ?? '';
    final destPath =
        (args[FetchArtifactTool.destPath] as String?)?.trim() ?? '';
    if (name.isEmpty || destPath.isEmpty) {
      return _toolError(
        req.id,
        'fetch_artifact requires a non-empty "name" and "destPath".',
      );
    }
    final overwrite = args[FetchArtifactTool.overwrite] as bool? ?? false;
    try {
      final result = await artifacts.fetch(
        fetcherMemberId: memberId,
        name: name,
        destPath: destPath,
        overwrite: overwrite,
      );
      return _ok(
        req.id,
        'Fetched "${result.name}" (${result.sizeBytes} bytes) to '
        '${result.finalPath}.',
      );
    } on ArtifactException catch (e) {
      return _toolError(req.id, e.toString());
    }
  }

  String _encodeTasks(List<TeamTask> tasks, String memberId) {
    if (tasks.isEmpty) return 'No tasks on the queue.';
    final caps = _bus.capabilitiesOf(memberId);
    final buffer = StringBuffer('Work queue (${tasks.length}):\n\n');
    buffer.write(tasks
        .map((t) => _formatTask(t, memberId: memberId, memberCaps: caps))
        .join('\n\n'));
    return buffer.toString().trimRight();
  }

  /// wait_for_message 返回的"已认领任务"。明确告知执行 + 完成后回报。
  String _encodeTaskAssignment(TeamTask t) {
    return 'ASSIGNED TASK (claimed for you from the shared work queue):\n'
        '${_formatTask(t, full: true)}\n\n'
        'Do this task now. When finished, call '
        'update_task(task_id: "${t.id}", status: "done" | "failed", result?), '
        'then call wait_for_message again.';
  }

  String _formatTask(
    TeamTask t, {
    bool full = false,
    String? memberId,
    Set<String>? memberCaps,
  }) {
    final lines = <String>[
      '--- ${t.id} [${t.status.name}] ---',
      'title: ${t.title}',
      if (t.assignee != null) 'assignee: ${t.assignee}',
      if (t.dependsOn.isNotEmpty) 'depends_on: ${t.dependsOn.join(', ')}',
      if (t.requiredCapabilities.isNotEmpty)
        'required_capabilities: ${t.requiredCapabilities.join(', ')}',
      if (memberId != null && memberCaps != null) ...[
        'eligible_for_you: ${TaskRouter.eligible(memberId, memberCaps, t)}',
        'match_score: ${TaskRouter.score(memberCaps, t)}',
      ],
      if (t.result != null && t.result!.isNotEmpty) 'result: ${t.result}',
      if (full) 'brief:\n${t.brief}',
    ];
    return lines.join('\n');
  }

  JsonRpcResponse _ok(Object? id, String text) => JsonRpcResponse.result(id, {
    'content': [
      {'type': 'text', 'text': text},
    ],
    'isError': false,
  });

  JsonRpcResponse _toolError(Object? id, String text) =>
      JsonRpcResponse.result(id, {
        'content': [
          {'type': 'text', 'text': text},
        ],
        'isError': true,
      });

  String _unknownRecipientHint() {
    final roster = _bus.rosterSnapshot().members;
    if (roster.isEmpty) return '';
    final lines = <String>[' Known recipients:'];
    for (final t in roster) {
      final p = t.profile;
      final alias = p.agentId.trim();
      if (alias.isNotEmpty && alias != p.memberId) {
        lines.add('- ${p.memberId} (agentId: $alias)');
      } else {
        lines.add('- ${p.memberId}');
      }
    }
    return lines.join('\n');
  }

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

}
