import 'dart:convert';

import '../../../utils/logging/logger.dart';
import '../artifacts/artifact_transfer_service.dart';
import '../cancellation.dart';
import '../team_bus.dart';
import 'jsonrpc.dart';
import 'mcp_method.dart';
import 'toolkit/mcp_tool_response.dart';
import 'toolkit/teammate_bus_tool_call.dart';
import 'toolkit/teammate_bus_tool_context.dart';
import 'toolkit/teammate_bus_tool_name.dart';
import 'toolkit/teammate_bus_tool_registry.dart';
import 'toolkit/wait_delivery.dart';
import 'tools/wait_for_message_tool.dart';
import 'wait_cancel_registry.dart';

export 'toolkit/wait_delivery.dart';

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
  final ArtifactTransferService? _artifacts;

  /// In-flight streaming `wait_for_message` calls keyed by JSON-RPC request id.
  final WaitCancelRegistry waitCancels;

  TeammateBusToolContext get _toolCtx => TeammateBusToolContext(
    bus: _bus,
    idGenerator: idGenerator,
    artifacts: _artifacts,
    onEnteredWaitLoop: _noteEnteredWaitLoop,
  );

  TeammateBusToolCall _toolCall(
    String memberId,
    Object? requestId,
    Map<String, Object?> arguments,
  ) => TeammateBusToolCall(
    ctx: _toolCtx,
    memberId: memberId,
    requestId: requestId,
    arguments: arguments,
  );

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
          'tools': listAdvertisedTeammateBusTools(_toolCtx),
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
  }) => WaitForMessageTool.beginStreamWait(
    _toolCall(memberId, req.id, req.toolArguments),
    cancel: cancel,
  );

  Future<JsonRpcResponse> _callTool(String memberId, JsonRpcRequest req) async {
    final tool = teammateBusToolByName(_toolCtx)[req.toolName];
    if (tool == null) {
      return McpToolResponse.invalidParams(
        req.id,
        'Unknown tool: ${req.params[McpParams.toolName]}',
      );
    }
    return tool.call(_toolCall(memberId, req.id, req.toolArguments));
  }
}
